using System.IO;
using Hanasu.Core.Audio;
using Hanasu.Core.Meetings;
using Hanasu.Core.Transcription;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace Hanasu.Windows.Services;

/// <summary>出力の機器 1 つ（WASAPI のエンドポイント）。会議で「相手」として録る</summary>
internal sealed record OutputDeviceInfo(string Id, string Name);

/// <summary>
/// 会議の 1 チャンネルを WASAPI で録り、16 kHz・モノラルの WAV に書き出す。
/// - 自分: マイク（WasapiCapture）
/// - 相手: 出力の機器のループバック（WasapiLoopbackCapture）。PC で鳴っている音（会議ツールの相手の声）を横取りせずに複製して受け取る
/// 音声入力の WasapiRecorder はメモリに溜めるが、会議は長いので溜めずにファイルへ書く。
/// 時刻は ChannelTimeline で録音開始からの共通の時間軸にそろえる（ループバックは無音の間データが来ないので、その分の無音を足す）。
/// </summary>
internal sealed class MeetingChannelRecorder : IMeetingChannelRecorder
{
    private readonly string deviceId;
    private readonly object gate = new();
    private readonly ChannelTimeline timeline = new();
    private WasapiCapture? capture;
    private MMDevice? device;
    private StreamingResampler? resampler;
    private WavStreamWriter? writer;
    private SampleConversion.Encoding encoding;
    private int channels;
    private Func<double>? elapsed;
    private TaskCompletionSource? stopped;
    private double level;

    public MeetingChannelRecorder(MeetingChannel channel, string deviceId)
    {
        Channel = channel;
        this.deviceId = deviceId;
    }

    public MeetingChannel Channel { get; }

    public double? StartOffset
    {
        get { lock (gate) return timeline.StartOffset; }
    }

    public double Level => Volatile.Read(ref level);

    public event EventHandler<Exception>? Faulted;

    /// <summary>使える出力の機器の一覧</summary>
    public static IReadOnlyList<OutputDeviceInfo> ListOutputs()
    {
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            return enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active)
                .Select(d =>
                {
                    using (d) return new OutputDeviceInfo(d.ID, d.FriendlyName);
                })
                .ToArray();
        }
        catch (Exception e) when (e is System.Runtime.InteropServices.COMException or InvalidOperationException)
        {
            return Array.Empty<OutputDeviceInfo>();
        }
    }

    public Task StartAsync(string wavPath, Func<double> elapsed, CancellationToken cancellationToken = default)
    {
        this.elapsed = elapsed;
        var flow = Channel == MeetingChannel.Me ? DataFlow.Capture : DataFlow.Render;
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            device = (deviceId.Length > 0 ? FindDevice(enumerator, deviceId) : null)
                ?? enumerator.GetDefaultAudioEndpoint(flow, flow == DataFlow.Capture ? Role.Communications : Role.Multimedia);
        }
        catch (System.Runtime.InteropServices.COMException e)
        {
            throw new TranscriptionException(Channel == MeetingChannel.Me
                ? "マイクが見つかりません。マイクがつながっているか、Windows の設定 → システム → サウンド で確かめてください。"
                : "音の出力の機器（スピーカー・ヘッドホン）が見つかりません。", "ms-settings:sound", e);
        }

        try
        {
            // ループバックは共有モードの形式（多くは 48 kHz・ステレオ・float）のまま受け取り、左右を混ぜて 16 kHz に落とす
            capture = Channel == MeetingChannel.Me
                ? new WasapiCapture(device, useEventSync: true, audioBufferMillisecondsLength: 100)
                : new WasapiLoopbackCapture(device);
            var format = capture.WaveFormat;
            encoding = WasapiRecorder.EncodingOf(format);
            channels = format.Channels;
            resampler = new StreamingResampler(format.SampleRate, AudioFormat.SampleRate);
            writer = new WavStreamWriter(wavPath);
            stopped = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            capture.DataAvailable += OnDataAvailable;
            capture.RecordingStopped += OnRecordingStopped;
            capture.StartRecording();
            AppLog.Write($"meeting {Channel} capture: {format.SampleRate} Hz, {format.Channels} ch, {format.BitsPerSample} bit");
        }
        catch (Exception e) when (e is System.Runtime.InteropServices.COMException or UnauthorizedAccessException or InvalidOperationException or ArgumentException or IOException)
        {
            Cleanup();
            if (Channel == MeetingChannel.Me && (e is UnauthorizedAccessException || (uint)e.HResult == 0x80070005))
            {
                throw new TranscriptionException(
                    "マイクの使用が許可されていません。Windows の設定 → プライバシーとセキュリティ → マイク で「デスクトップ アプリがマイクにアクセスできるようにする」をオンにしてください。",
                    "ms-settings:privacy-microphone", e);
            }
            throw new TranscriptionException($"{(Channel == MeetingChannel.Me ? "マイク" : "PC の音")}の録音を始められませんでした: {e.Message}", inner: e);
        }
        return Task.CompletedTask;
    }

    public async Task StopAsync()
    {
        var c = capture;
        if (c is null) return;
        try { c.StopRecording(); } catch (InvalidOperationException) { }
        if (stopped is not null) await Task.WhenAny(stopped.Task, Task.Delay(2000)).ConfigureAwait(false);
        lock (gate)
        {
            if (resampler is not null && writer is not null) writer.Write(resampler.Flush());
            writer?.Dispose();
            writer = null;
        }
        Cleanup();
    }

    public async ValueTask DisposeAsync()
    {
        if (capture is not null) await StopAsync().ConfigureAwait(false);
        Cleanup();
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        if (e.BytesRecorded == 0 || resampler is null) return;
        var mono = SampleConversion.ToMonoFloat(e.Buffer.AsSpan(0, e.BytesRecorded), encoding, channels);
        lock (gate)
        {
            if (writer is null) return;
            var converted = resampler.Process(mono);
            if (converted.Length == 0) return;
            var silence = timeline.Advance(elapsed?.Invoke() ?? 0, converted.Length);
            writer.WriteSilence(silence);
            writer.Write(converted);
            Volatile.Write(ref level, MeetingAudio.Rms(converted));
        }
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        if (e.Exception is not null) Faulted?.Invoke(this, e.Exception);
        stopped?.TrySetResult();
    }

    private void Cleanup()
    {
        if (capture is not null)
        {
            capture.DataAvailable -= OnDataAvailable;
            capture.RecordingStopped -= OnRecordingStopped;
            capture.Dispose();
            capture = null;
        }
        lock (gate)
        {
            writer?.Dispose();
            writer = null;
        }
        device?.Dispose();
        device = null;
    }

    private static MMDevice? FindDevice(MMDeviceEnumerator enumerator, string id)
    {
        try
        {
            var d = enumerator.GetDevice(id);
            if (d.State == DeviceState.Active) return d;
            d.Dispose();
        }
        catch (System.Runtime.InteropServices.COMException) { }
        return null;
    }
}

using Hanasu.Core.Audio;
using Hanasu.Core.Transcription;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace Hanasu.Windows.Services;

/// <summary>マイク 1 つ（WASAPI のエンドポイント）。</summary>
internal sealed record MicrophoneInfo(string Id, string Name);

/// <summary>
/// WASAPI（NAudio の WasapiCapture）でマイクから録音し、16 kHz・モノラルの float に変換して溜める。
/// 共有モードの形式（多くは 48 kHz・ステレオ・float）のまま受け取り、Core の StreamingResampler で落とす。
/// 会議の記録でもマイク側はこのクラスを使う（システム音声は WasapiLoopbackCapture で同じ形にできる）。
/// </summary>
internal sealed class WasapiRecorder : IAudioRecorder
{
    private readonly object gate = new();
    private readonly List<float> samples = new();
    private WasapiCapture? capture;
    private MMDevice? device;
    private StreamingResampler? resampler;
    private SampleConversion.Encoding encoding;
    private int channels;
    private TaskCompletionSource? stopped;

    public event EventHandler<float[]>? SamplesAvailable;
    public event EventHandler<Exception>? Faulted;

    /// <summary>使えるマイクの一覧</summary>
    public static IReadOnlyList<MicrophoneInfo> ListMicrophones()
    {
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            return enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active)
                .Select(d =>
                {
                    using (d) return new MicrophoneInfo(d.ID, d.FriendlyName);
                })
                .ToArray();
        }
        catch (Exception e) when (e is System.Runtime.InteropServices.COMException or InvalidOperationException)
        {
            return Array.Empty<MicrophoneInfo>();
        }
    }

    public Task StartAsync(string deviceId, CancellationToken cancellationToken = default)
    {
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            device = string.IsNullOrEmpty(deviceId)
                ? enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console)
                : FindDevice(enumerator, deviceId) ?? enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
        }
        catch (System.Runtime.InteropServices.COMException e)
        {
            throw new TranscriptionException("マイクが見つかりません。マイクがつながっているか、Windows の設定 → システム → サウンド で確かめてください。",
                "ms-settings:sound", e);
        }

        try
        {
            capture = new WasapiCapture(device, useEventSync: true, audioBufferMillisecondsLength: 100);
            var format = capture.WaveFormat;
            encoding = EncodingOf(format);
            channels = format.Channels;
            resampler = new StreamingResampler(format.SampleRate, AudioFormat.SampleRate);
            lock (gate) samples.Clear();
            stopped = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            capture.DataAvailable += OnDataAvailable;
            capture.RecordingStopped += OnRecordingStopped;
            capture.StartRecording();
        }
        catch (Exception e) when (e is System.Runtime.InteropServices.COMException or UnauthorizedAccessException or InvalidOperationException or ArgumentException)
        {
            Cleanup();
            // E_ACCESSDENIED: プライバシー設定でマイクが許可されていない
            if (e is UnauthorizedAccessException || (uint)e.HResult == 0x80070005)
            {
                throw new TranscriptionException(
                    "マイクの使用が許可されていません。Windows の設定 → プライバシーとセキュリティ → マイク で「デスクトップ アプリがマイクにアクセスできるようにする」をオンにしてください。",
                    "ms-settings:privacy-microphone", e);
            }
            throw new TranscriptionException($"マイクで録音を始められませんでした: {e.Message}", inner: e);
        }
        return Task.CompletedTask;
    }

    public async Task<float[]> StopAsync()
    {
        var c = capture;
        if (c is null) return Array.Empty<float>();
        try { c.StopRecording(); } catch (InvalidOperationException) { }
        if (stopped is not null) await Task.WhenAny(stopped.Task, Task.Delay(2000)).ConfigureAwait(false);
        float[] result;
        lock (gate)
        {
            if (resampler is not null) samples.AddRange(resampler.Flush());
            result = samples.ToArray();
            samples.Clear();
        }
        Cleanup();
        return result;
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
        float[] converted;
        lock (gate)
        {
            converted = resampler.Process(mono);
            samples.AddRange(converted);
        }
        if (converted.Length > 0) SamplesAvailable?.Invoke(this, converted);
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

    private static readonly Guid SubtypeIeeeFloat = new("00000003-0000-0010-8000-00aa00389b71");

    internal static SampleConversion.Encoding EncodingOf(WaveFormat format)
    {
        var isFloat = format.Encoding == WaveFormatEncoding.IeeeFloat
            || (format is WaveFormatExtensible ext && ext.SubFormat == SubtypeIeeeFloat);
        if (isFloat && format.BitsPerSample == 32) return SampleConversion.Encoding.Float32;
        return format.BitsPerSample switch
        {
            16 => SampleConversion.Encoding.Pcm16,
            24 => SampleConversion.Encoding.Pcm24,
            32 => SampleConversion.Encoding.Pcm32,
            _ => throw new ArgumentException($"対応していない録音の形式です（{format}）"),
        };
    }
}

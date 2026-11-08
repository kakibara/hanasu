using System.Buffers.Binary;
using System.Text;

namespace Hanasu.Core.Audio;

/// <summary>
/// 会議の 1 チャンネル分の音声を、録りながら 16 kHz・モノラル・16 bit の WAV に書き出す。
/// 長さ（ヘッダーの大きさの欄）は数秒ごとに書き直すので、アプリが落ちても途中までの音声を読める。
/// メモリに溜めないので、長い会議でも使うメモリは増えない。
/// </summary>
public sealed class WavStreamWriter : IDisposable
{
    private const int HeaderLength = 44;
    private readonly FileStream stream;
    private readonly object gate = new();
    private readonly int sampleRate;
    private long dataLength;
    private long lastHeaderUpdate;
    private bool disposed;

    public string Path { get; }

    /// <summary>書いたサンプル数</summary>
    public long SampleCount
    {
        get { lock (gate) return dataLength / 2; }
    }

    public WavStreamWriter(string path, int sampleRate = AudioFormat.SampleRate)
    {
        Path = path;
        this.sampleRate = sampleRate;
        stream = new FileStream(path, FileMode.Create, FileAccess.ReadWrite, FileShare.Read);
        stream.Write(Header(0, sampleRate));
    }

    public void Write(ReadOnlySpan<float> samples)
    {
        if (samples.Length == 0) return;
        var bytes = new byte[samples.Length * 2];
        for (var i = 0; i < samples.Length; i++)
        {
            var v = Math.Clamp(samples[i], -1f, 1f);
            BinaryPrimitives.WriteInt16LittleEndian(bytes.AsSpan(i * 2), (short)Math.Round(v * 32767));
        }
        lock (gate)
        {
            if (disposed) return;
            stream.Write(bytes);
            dataLength += bytes.Length;
            // 5 秒ごとにヘッダーを書き直す
            if (dataLength - lastHeaderUpdate >= sampleRate * 2L * 5) UpdateHeader();
        }
    }

    /// <summary>無音を足す（ループバックの音が途切れていた分を埋める）</summary>
    public void WriteSilence(int count)
    {
        if (count <= 0) return;
        Write(new float[count]);
    }

    // 要件: REQ-MTG-043
    // 設計判断: DEC-MTG-111
    /// <summary>このクラスで書いた WAV を、先頭から seconds 秒までに切り詰める（ヘッダーの長さも直す）。もともと短ければ何もしない</summary>
    public static void Truncate(string path, double seconds, int sampleRate = AudioFormat.SampleRate)
    {
        if (!File.Exists(path)) return;
        using var stream = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        var dataLength = Math.Max(0, stream.Length - HeaderLength);
        var keep = Math.Max(0, (long)Math.Round(seconds * sampleRate)) * 2;
        if (keep >= dataLength) return;
        stream.SetLength(HeaderLength + keep);
        stream.Position = 0;
        stream.Write(Header(keep, sampleRate));
    }

    private void UpdateHeader()
    {
        var position = stream.Position;
        stream.Position = 0;
        stream.Write(Header(dataLength, sampleRate));
        stream.Position = position;
        stream.Flush();
        lastHeaderUpdate = dataLength;
    }

    internal static byte[] Header(long dataLength, int sampleRate)
    {
        var length = (int)Math.Min(dataLength, int.MaxValue - HeaderLength);
        var header = new byte[HeaderLength];
        var span = header.AsSpan();
        Encoding.ASCII.GetBytes("RIFF").CopyTo(span);
        BinaryPrimitives.WriteInt32LittleEndian(span[4..], 36 + length);
        Encoding.ASCII.GetBytes("WAVE").CopyTo(span[8..]);
        Encoding.ASCII.GetBytes("fmt ").CopyTo(span[12..]);
        BinaryPrimitives.WriteInt32LittleEndian(span[16..], 16);
        BinaryPrimitives.WriteInt16LittleEndian(span[20..], 1);
        BinaryPrimitives.WriteInt16LittleEndian(span[22..], 1);
        BinaryPrimitives.WriteInt32LittleEndian(span[24..], sampleRate);
        BinaryPrimitives.WriteInt32LittleEndian(span[28..], sampleRate * 2);
        BinaryPrimitives.WriteInt16LittleEndian(span[32..], 2);
        BinaryPrimitives.WriteInt16LittleEndian(span[34..], 16);
        Encoding.ASCII.GetBytes("data").CopyTo(span[36..]);
        BinaryPrimitives.WriteInt32LittleEndian(span[40..], length);
        return header;
    }

    public void Dispose()
    {
        lock (gate)
        {
            if (disposed) return;
            UpdateHeader();
            disposed = true;
            stream.Dispose();
        }
    }
}

/// <summary>
/// チャンネルの音声を、録音開始からの共通の時間軸にそろえる。
/// - 最初の音が届いた時刻を「このチャンネルの開始のずれ」（StartOffset）として覚える（Mac 版の audioStartOffset と同じ考え）。
/// - WASAPI のループバックは、PC が何も鳴らしていない間はデータを渡してこない。届いた時刻と、それまでに書いた長さの差が
///   開いていたら、その分の無音を足して時刻がずれないようにする。
/// </summary>
public sealed class ChannelTimeline
{
    /// <summary>このくらいまでの差は、届き方のゆらぎとみなして埋めない（秒）</summary>
    public const double Tolerance = 0.25;

    private readonly int sampleRate;
    private long written;

    public ChannelTimeline(int sampleRate = AudioFormat.SampleRate)
    {
        this.sampleRate = sampleRate;
    }

    /// <summary>最初の音の、録音開始からの秒数。まだ何も届いていなければ null</summary>
    public double? StartOffset { get; private set; }

    /// <summary>書いた長さ（秒）。足した無音を含む</summary>
    public double WrittenSeconds => written / (double)sampleRate;

    /// <summary>
    /// 音が届いたときに呼ぶ。前に足すべき無音のサンプル数を返す。
    /// </summary>
    /// <param name="elapsedAtArrival">届いた時点の、録音開始からの秒数</param>
    /// <param name="chunkSamples">届いた音のサンプル数（変換後）</param>
    public int Advance(double elapsedAtArrival, int chunkSamples)
    {
        var chunkStart = elapsedAtArrival - chunkSamples / (double)sampleRate;
        if (StartOffset is not { } offset)
        {
            StartOffset = Math.Max(0, chunkStart);
            written = chunkSamples;
            return 0;
        }
        var gap = chunkStart - (offset + WrittenSeconds);
        var silence = gap > Tolerance ? (int)Math.Round(gap * sampleRate) : 0;
        written += silence + chunkSamples;
        return silence;
    }
}

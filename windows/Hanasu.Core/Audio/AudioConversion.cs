using System.Buffers.Binary;

namespace Hanasu.Core.Audio;

/// <summary>
/// 文字起こしに使う音声の形式。どのエンジンにも 16 kHz・モノラル・float（-1〜1）で渡す。
/// 会議の記録でも、マイクとシステム音声をそれぞれこの形にそろえる。
/// </summary>
public static class AudioFormat
{
    public const int SampleRate = 16000;
}

/// <summary>
/// 任意のサンプリング周波数の音声を少しずつ受け取り、別の周波数に変換する（窓付き sinc 補間）。
/// WASAPI の共有モードは 48 kHz などで渡してくるので、16 kHz に落とすのに使う。
/// ダウンサンプリングでは、折り返し雑音を防ぐため、出力のナイキスト周波数でローパスをかける。
/// </summary>
public sealed class StreamingResampler
{
    private const int LobeCount = 8;
    private readonly int inputRate;
    private readonly int outputRate;
    private readonly double step;      // 出力 1 サンプルあたりの入力サンプル数
    private readonly double cutoff;    // 入力の周波数に対するカットオフ（0〜1、1 = 入力のナイキスト）
    private readonly int halfWidth;    // 片側の窓の幅（入力サンプル数）
    private readonly List<float> buffer = new();
    private double position;           // 次に出す出力サンプルの位置（buffer の添字）
    private long totalInput;           // これまでに受け取った入力サンプル数
    private long produced;             // これまでに出した出力サンプル数

    public StreamingResampler(int inputRate, int outputRate = AudioFormat.SampleRate)
    {
        if (inputRate <= 0 || outputRate <= 0) throw new ArgumentOutOfRangeException(nameof(inputRate));
        this.inputRate = inputRate;
        this.outputRate = outputRate;
        step = (double)inputRate / outputRate;
        cutoff = Math.Min(1.0, (double)outputRate / inputRate);
        halfWidth = (int)Math.Ceiling(LobeCount / cutoff);
    }

    public int InputRate => inputRate;
    public int OutputRate => outputRate;

    /// <summary>入力を足し、出せるだけの出力を返す</summary>
    public float[] Process(ReadOnlySpan<float> input)
    {
        if (inputRate == outputRate) return input.ToArray();
        foreach (var x in input) buffer.Add(x);
        totalInput += input.Length;
        var output = new List<float>((int)(input.Length / step) + 2);
        while (position + halfWidth < buffer.Count)
        {
            output.Add(SampleAt(position));
            position += step;
            produced++;
        }
        // 次の出力に要らない古い入力を捨てる
        var drop = (int)Math.Floor(position) - halfWidth;
        if (drop > 0)
        {
            buffer.RemoveRange(0, drop);
            position -= drop;
        }
        return output.ToArray();
    }

    /// <summary>残りを出し切る（終わりに無音を足して、窓の右側を埋める）。出力の長さは 入力の長さ × 出力/入力 にそろえる</summary>
    public float[] Flush()
    {
        if (inputRate == outputRate) return Array.Empty<float>();
        var expected = (long)Math.Ceiling(totalInput / step);
        var padding = new float[halfWidth + (int)Math.Ceiling(step) + 1];
        var countedInput = totalInput;
        var output = new List<float>(Process(padding));
        totalInput = countedInput;  // 足した無音は入力の長さに数えない
        var excess = (int)Math.Max(0, produced - expected);
        if (excess > 0)
        {
            output.RemoveRange(Math.Max(0, output.Count - excess), Math.Min(excess, output.Count));
            produced -= excess;
        }
        return output.ToArray();
    }

    private float SampleAt(double p)
    {
        var center = (int)Math.Floor(p);
        double sum = 0, weightSum = 0;
        for (var i = center - halfWidth + 1; i <= center + halfWidth; i++)
        {
            var t = (p - i) * cutoff;
            var w = Lanczos(t);
            weightSum += w;
            // 先頭より前は無音として扱う
            if (i >= 0 && i < buffer.Count) sum += buffer[i] * w;
        }
        return weightSum == 0 ? 0 : (float)(sum / weightSum);
    }

    private static double Lanczos(double x)
    {
        if (Math.Abs(x) < 1e-9) return 1;
        if (Math.Abs(x) >= LobeCount) return 0;
        var px = Math.PI * x;
        return LobeCount * Math.Sin(px) * Math.Sin(px / LobeCount) / (px * px);
    }
}

/// <summary>録音したバイト列を float に直し、モノラルに混ぜる。</summary>
public static class SampleConversion
{
    public enum Encoding { Float32, Pcm16, Pcm24, Pcm32 }

    /// <summary>インターリーブされたバイト列を、モノラルの float にする（各チャンネルの平均）</summary>
    public static float[] ToMonoFloat(ReadOnlySpan<byte> data, Encoding encoding, int channels)
    {
        if (channels <= 0) throw new ArgumentOutOfRangeException(nameof(channels));
        var bytesPerSample = encoding switch
        {
            Encoding.Float32 or Encoding.Pcm32 => 4,
            Encoding.Pcm24 => 3,
            _ => 2,
        };
        var frameSize = bytesPerSample * channels;
        var frames = data.Length / frameSize;
        var result = new float[frames];
        for (var f = 0; f < frames; f++)
        {
            double sum = 0;
            for (var c = 0; c < channels; c++)
            {
                var s = data.Slice(f * frameSize + c * bytesPerSample, bytesPerSample);
                sum += encoding switch
                {
                    Encoding.Float32 => BinaryPrimitives.ReadSingleLittleEndian(s),
                    Encoding.Pcm16 => BinaryPrimitives.ReadInt16LittleEndian(s) / 32768.0,
                    Encoding.Pcm24 => ((s[0] | (s[1] << 8) | (s[2] << 16)) << 8 >> 8) / 8388608.0,
                    Encoding.Pcm32 => BinaryPrimitives.ReadInt32LittleEndian(s) / 2147483648.0,
                    _ => 0,
                };
            }
            result[f] = (float)(sum / channels);
        }
        return result;
    }
}

/// <summary>音声の大きさを調べる。</summary>
public static class AudioAnalysis
{
    /// <summary>30 ms ごとの RMS のうち最大のもの（0〜1）</summary>
    public static double PeakWindowRms(ReadOnlySpan<float> samples, int sampleRate = AudioFormat.SampleRate)
    {
        var window = Math.Max(1, sampleRate * 30 / 1000);
        double peak = 0;
        for (var start = 0; start < samples.Length; start += window)
        {
            var span = samples.Slice(start, Math.Min(window, samples.Length - start));
            double sum = 0;
            foreach (var x in span) sum += x * x;
            peak = Math.Max(peak, Math.Sqrt(sum / span.Length));
        }
        return peak;
    }

    /// <summary>
    /// 話し声がなさそうなとき true。Whisper は無音に「ご視聴ありがとうございました」などを書きがちなので、
    /// 送る前に止める（Gemini に無駄に送らないためでもある）。しきい値は約 -46 dBFS。
    /// </summary>
    public static bool IsSilent(ReadOnlySpan<float> samples, int sampleRate = AudioFormat.SampleRate, double threshold = 0.005) =>
        samples.Length < sampleRate / 4 || PeakWindowRms(samples, sampleRate) < threshold;
}

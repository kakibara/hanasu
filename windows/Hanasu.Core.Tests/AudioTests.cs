using System.Buffers.Binary;
using Hanasu.Core.Audio;

namespace Hanasu.Core.Tests;

public class AudioTests
{
    private static float[] Sine(double frequency, int rate, double seconds, double amplitude = 0.5)
    {
        var n = (int)(rate * seconds);
        return Enumerable.Range(0, n).Select(i => (float)(amplitude * Math.Sin(2 * Math.PI * frequency * i / rate))).ToArray();
    }

    private static double Rms(ReadOnlySpan<float> x)
    {
        double sum = 0;
        foreach (var v in x) sum += v * v;
        return Math.Sqrt(sum / x.Length);
    }

    [Fact]
    public void ResamplesToExpectedLengthInChunks()
    {
        var input = Sine(440, 48000, 1.0);
        var resampler = new StreamingResampler(48000);
        var output = new List<float>();
        // WASAPI のように 10 ms ずつ渡す
        for (var i = 0; i < input.Length; i += 480) output.AddRange(resampler.Process(input.AsSpan(i, Math.Min(480, input.Length - i))));
        output.AddRange(resampler.Flush());
        Assert.Equal(16000, output.Count);
    }

    [Theory]
    [InlineData(48000)]
    [InlineData(44100)]
    [InlineData(22050)]
    public void KeepsSpeechBandAndRemovesAliases(int inputRate)
    {
        var resampler = new StreamingResampler(inputRate);
        var speech = resampler.Process(Sine(1000, inputRate, 0.5));
        // 1 kHz は振幅を保つ（窓の端は除いて見る）
        Assert.InRange(Rms(speech.AsSpan(800, 4000)), 0.5 / Math.Sqrt(2) * 0.95, 0.5 / Math.Sqrt(2) * 1.05);

        if (inputRate > 32000)
        {
            // 12 kHz は 16 kHz では表せない。折り返して 4 kHz として残らないよう、ほぼ消える
            var alias = new StreamingResampler(inputRate).Process(Sine(12000, inputRate, 0.5));
            Assert.True(Rms(alias.AsSpan(800, 4000)) < 0.02);
        }
    }

    [Fact]
    public void SameRatePassesThrough()
    {
        var input = Sine(300, 16000, 0.1);
        var resampler = new StreamingResampler(16000);
        Assert.Equal(input, resampler.Process(input));
        Assert.Empty(resampler.Flush());
    }

    [Fact]
    public void ConvertsInterleavedSamplesToMono()
    {
        // 2 チャンネルの float: (0.5, -0.5) と (1, 0)
        var bytes = new byte[16];
        BinaryPrimitives.WriteSingleLittleEndian(bytes.AsSpan(0), 0.5f);
        BinaryPrimitives.WriteSingleLittleEndian(bytes.AsSpan(4), -0.5f);
        BinaryPrimitives.WriteSingleLittleEndian(bytes.AsSpan(8), 1f);
        BinaryPrimitives.WriteSingleLittleEndian(bytes.AsSpan(12), 0f);
        Assert.Equal([0f, 0.5f], SampleConversion.ToMonoFloat(bytes, SampleConversion.Encoding.Float32, 2));

        var pcm16 = new byte[4];
        BinaryPrimitives.WriteInt16LittleEndian(pcm16, 16384);
        BinaryPrimitives.WriteInt16LittleEndian(pcm16.AsSpan(2), -32768);
        Assert.Equal([0.5f, -1f], SampleConversion.ToMonoFloat(pcm16, SampleConversion.Encoding.Pcm16, 1));

        var pcm24 = new byte[] { 0x00, 0x00, 0xC0 };  // -0.5
        Assert.Equal([-0.5f], SampleConversion.ToMonoFloat(pcm24, SampleConversion.Encoding.Pcm24, 1));
    }

    [Fact]
    public void WavRoundTrips()
    {
        var samples = Sine(440, 16000, 0.25);
        var wav = WavFile.Encode(samples);
        Assert.Equal(44 + samples.Length * 2, wav.Length);
        var (decoded, rate) = WavFile.Decode(wav);
        Assert.Equal(16000, rate);
        Assert.Equal(samples.Length, decoded.Length);
        Assert.All(samples.Zip(decoded), p => Assert.InRange(p.Second - p.First, -0.001f, 0.001f));

        // 44.1 kHz の WAV を 16 kHz に直して読む
        var wav44 = WavFile.Encode(Sine(440, 44100, 0.5), 44100);
        Assert.Equal(8000, WavFile.DecodeTo16kMono(wav44).Length);
        Assert.Throws<InvalidDataException>(() => WavFile.Decode(new byte[20]));
    }

    [Fact]
    public void DetectsSilence()
    {
        Assert.True(AudioAnalysis.IsSilent(new float[16000]));
        Assert.True(AudioAnalysis.IsSilent(Sine(300, 16000, 0.1)));  // 短すぎる
        Assert.True(AudioAnalysis.IsSilent(Sine(300, 16000, 1, amplitude: 0.002)));
        Assert.False(AudioAnalysis.IsSilent(Sine(300, 16000, 1, amplitude: 0.1)));
    }

    [Fact]
    public void ToneIsAValidWav()
    {
        var (samples, rate) = WavFile.Decode(ToneGenerator.Tones((880, 60), (1320, 60)));
        Assert.Equal(22050, rate);
        Assert.Equal(22050 * 120 / 1000, samples.Length);
    }
}

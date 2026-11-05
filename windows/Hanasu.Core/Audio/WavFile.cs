using System.Buffers.Binary;
using System.Text;

namespace Hanasu.Core.Audio;

/// <summary>WAV（RIFF）の読み書き。Gemini に送る音声と、確認用の CLI で使う。</summary>
public static class WavFile
{
    /// <summary>モノラル float を 16 bit PCM の WAV にする</summary>
    public static byte[] Encode(ReadOnlySpan<float> samples, int sampleRate = AudioFormat.SampleRate)
    {
        const short channels = 1;
        const short bitsPerSample = 16;
        var dataLength = samples.Length * 2;
        var bytes = new byte[44 + dataLength];
        var span = bytes.AsSpan();
        Encoding.ASCII.GetBytes("RIFF").CopyTo(span);
        BinaryPrimitives.WriteInt32LittleEndian(span[4..], 36 + dataLength);
        Encoding.ASCII.GetBytes("WAVE").CopyTo(span[8..]);
        Encoding.ASCII.GetBytes("fmt ").CopyTo(span[12..]);
        BinaryPrimitives.WriteInt32LittleEndian(span[16..], 16);
        BinaryPrimitives.WriteInt16LittleEndian(span[20..], 1);  // PCM
        BinaryPrimitives.WriteInt16LittleEndian(span[22..], channels);
        BinaryPrimitives.WriteInt32LittleEndian(span[24..], sampleRate);
        BinaryPrimitives.WriteInt32LittleEndian(span[28..], sampleRate * channels * bitsPerSample / 8);
        BinaryPrimitives.WriteInt16LittleEndian(span[32..], (short)(channels * bitsPerSample / 8));
        BinaryPrimitives.WriteInt16LittleEndian(span[34..], bitsPerSample);
        Encoding.ASCII.GetBytes("data").CopyTo(span[36..]);
        BinaryPrimitives.WriteInt32LittleEndian(span[40..], dataLength);
        for (var i = 0; i < samples.Length; i++)
        {
            var v = Math.Clamp(samples[i], -1f, 1f);
            BinaryPrimitives.WriteInt16LittleEndian(span[(44 + i * 2)..], (short)Math.Round(v * 32767));
        }
        return bytes;
    }

    /// <summary>WAV を読み、16 kHz・モノラルの float にする（PCM 16/24/32 bit と float 32 bit に対応）</summary>
    public static float[] DecodeTo16kMono(ReadOnlySpan<byte> wav)
    {
        var (samples, rate) = Decode(wav);
        if (rate == AudioFormat.SampleRate) return samples;
        var resampler = new StreamingResampler(rate);
        var head = resampler.Process(samples);
        var tail = resampler.Flush();
        return [.. head, .. tail];
    }

    /// <summary>WAV を読み、モノラルの float とサンプリング周波数を返す</summary>
    public static (float[] Samples, int SampleRate) Decode(ReadOnlySpan<byte> wav)
    {
        if (wav.Length < 12 || Encoding.ASCII.GetString(wav[..4]) != "RIFF" || Encoding.ASCII.GetString(wav[8..12]) != "WAVE")
        {
            throw new InvalidDataException(Strings.Wav_NotWav);
        }
        int format = 0, channels = 0, rate = 0, bits = 0;
        var offset = 12;
        while (offset + 8 <= wav.Length)
        {
            var id = Encoding.ASCII.GetString(wav.Slice(offset, 4));
            var size = BinaryPrimitives.ReadInt32LittleEndian(wav[(offset + 4)..]);
            var body = offset + 8;
            if (id == "fmt ")
            {
                format = BinaryPrimitives.ReadInt16LittleEndian(wav[body..]);
                channels = BinaryPrimitives.ReadInt16LittleEndian(wav[(body + 2)..]);
                rate = BinaryPrimitives.ReadInt32LittleEndian(wav[(body + 4)..]);
                bits = BinaryPrimitives.ReadInt16LittleEndian(wav[(body + 14)..]);
                if (format == 0xFFFE && size >= 26)  // WAVE_FORMAT_EXTENSIBLE: サブフォーマットの先頭 2 バイトが形式
                {
                    format = BinaryPrimitives.ReadInt16LittleEndian(wav[(body + 24)..]);
                }
            }
            else if (id == "data")
            {
                if (channels == 0) throw new InvalidDataException(Strings.Wav_NoFmt);
                var length = Math.Min(size, wav.Length - body);
                var encoding = (format, bits) switch
                {
                    (3, 32) => SampleConversion.Encoding.Float32,
                    (1, 16) => SampleConversion.Encoding.Pcm16,
                    (1, 24) => SampleConversion.Encoding.Pcm24,
                    (1, 32) => SampleConversion.Encoding.Pcm32,
                    _ => throw new InvalidDataException(string.Format(Strings.Wav_Unsupported, format, bits)),
                };
                return (SampleConversion.ToMonoFloat(wav.Slice(body, length), encoding, channels), rate);
            }
            offset = body + size + (size & 1);
        }
        throw new InvalidDataException(Strings.Wav_NoData);
    }
}

/// <summary>効果音（短い音）を作る。録音の開始・停止・エラーで鳴らす。</summary>
public static class ToneGenerator
{
    /// <summary>正弦波を続けて鳴らす WAV（周波数 Hz と長さ ms の組）</summary>
    public static byte[] Tones(params (double Frequency, int Milliseconds)[] tones)
    {
        const int rate = 22050;
        var samples = new List<float>();
        foreach (var (frequency, ms) in tones)
        {
            var count = rate * ms / 1000;
            for (var i = 0; i < count; i++)
            {
                // 端でぷつっと鳴らないよう、5 ms で立ち上げ・立ち下げる
                var fade = Math.Min(1.0, Math.Min(i, count - 1 - i) / (rate * 0.005));
                samples.Add((float)(Math.Sin(2 * Math.PI * frequency * i / rate) * 0.25 * fade));
            }
        }
        return WavFile.Encode(samples.ToArray(), rate);
    }
}

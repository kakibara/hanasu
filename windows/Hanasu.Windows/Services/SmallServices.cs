using System.Diagnostics;
using System.IO;
using System.Media;
using System.Text;
using Hanasu.Core;
using Hanasu.Core.Audio;
using Hanasu.Core.Dictation;
using Hanasu.Core.Settings;

namespace Hanasu.Windows.Services;

/// <summary>録音の開始・停止・エラーの効果音。音は Core の ToneGenerator で作る（Windows の通知音は大きくて長いため）。</summary>
internal sealed class SoundService
{
    // SoundPlayer.Play は非同期で鳴らすので、鳴り終わるまで手放さないよう使い回す
    private readonly Dictionary<SoundCue, SoundPlayer> players = new()
    {
        [SoundCue.Start] = Load(ToneGenerator.Tones((880, 70))),
        [SoundCue.Stop] = Load(ToneGenerator.Tones((660, 70))),
        [SoundCue.Error] = Load(ToneGenerator.Tones((330, 120), (247, 160))),
    };

    private static SoundPlayer Load(byte[] wav)
    {
        var player = new SoundPlayer(new MemoryStream(wav));
        player.Load();
        return player;
    }

    public void Play(SoundCue cue)
    {
        try
        {
            players[cue].Play();
        }
        catch (Exception e) when (e is InvalidOperationException or IOException)
        {
            AppLog.Write($"sound failed: {e.Message}");
        }
    }
}

internal static class Shell
{
    /// <summary>ms-settings: や https: を既定のアプリで開く</summary>
    public static void Open(string target)
    {
        try
        {
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            AppLog.Write($"open failed: {target}: {e.Message}");
        }
    }
}

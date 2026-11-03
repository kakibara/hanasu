using System.Diagnostics;
using System.IO;
using System.Media;
using System.Security.Cryptography;
using System.Text;
using Hanasu.Core;
using Hanasu.Core.Audio;
using Hanasu.Core.Dictation;
using Hanasu.Core.Settings;

namespace Hanasu.Windows.Services;

/// <summary>
/// DPAPI（CurrentUser）。同じ Windows ユーザーでしか復号できない（同じユーザーで動くほかのプロセスは復号できる。docs/design/security-windows.md）。
/// エントロピーは SecretStore が種類ごとに決める。
/// </summary>
// 設計判断: DEC-COM-144
internal sealed class DpapiDataProtector : IDataProtector
{
    public byte[] Protect(byte[] data, byte[] entropy) => ProtectedData.Protect(data, entropy, DataProtectionScope.CurrentUser);

    public byte[]? Unprotect(byte[] data, byte[] entropy)
    {
        try
        {
            return ProtectedData.Unprotect(data, entropy, DataProtectionScope.CurrentUser);
        }
        catch (CryptographicException)
        {
            return null;
        }
    }
}

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

/// <summary>
/// 動作の記録（%LOCALAPPDATA%\Hanasu\Logs\hanasu.log）。文字起こし・会議の中身は書かない。
/// 念のため、API キーやトークンに見える文字列は伏せてから書く（SecretRedactor）。
/// </summary>
// 設計判断: DEC-COM-147
internal static class AppLog
{
    private static readonly object Gate = new();
    private static readonly string FilePath = Path.Combine(HanasuPaths.LocalDataDirectory, "Logs", "hanasu.log");

    public static string Directory => Path.GetDirectoryName(FilePath)!;

    public static void Write(string message)
    {
        message = SecretRedactor.Redact(message);
        Debug.WriteLine(message);
        try
        {
            lock (Gate)
            {
                System.IO.Directory.CreateDirectory(Directory);
                var info = new FileInfo(FilePath);
                // 1 MB を超えたら 1 世代だけ残して作り直す
                if (info.Exists && info.Length > 1_000_000) File.Move(FilePath, FilePath + ".1", overwrite: true);
                File.AppendAllText(FilePath, $"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss.fff} {message}{Environment.NewLine}");
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
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

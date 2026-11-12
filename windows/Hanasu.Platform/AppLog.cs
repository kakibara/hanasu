using System.Diagnostics;
using Hanasu.Core;
using Hanasu.Core.Settings;

namespace Hanasu.Platform;

/// <summary>
/// 動作の記録（%LOCALAPPDATA%\Hanasu\Logs\hanasu.log）。文字起こし・会議の中身は書かない。
/// 念のため、API キーやトークンに見える文字列は伏せてから書く（SecretRedactor）。
/// </summary>
// 設計判断: DEC-COM-147
public static class AppLog
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

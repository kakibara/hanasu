using System.Text;

namespace Hanasu.Core.IO;

// 要件: REQ-COM-183
// 設計判断: DEC-COM-194
/// <summary>
/// アプリと hanasu コマンドが同じファイルを読み書きしても、互いに失敗しないための読み方と置き換え方。
/// Windows では、ほかのプロセスが削除の共有（FILE_SHARE_DELETE）なしで開いている間、置き換え（MoveFileEx）が失敗する。
/// 読む側は削除の共有つきで開いてすぐ閉じ、置き換える側は共有違反のときだけ短くやり直す。
/// </summary>
public static class SharedFile
{
    /// <summary>やり直しの間隔と回数（合わせて最大 1 秒）</summary>
    public static readonly TimeSpan RetryDelay = TimeSpan.FromMilliseconds(50);
    public const int MaxAttempts = 20;

    /// <summary>置き換えを妨げない開き方（読み書きと削除を共有する）で、UTF-8 の文を読む（先頭の BOM は外す）</summary>
    public static string ReadAllText(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var reader = new StreamReader(stream, new UTF8Encoding(false), detectEncodingFromByteOrderMarks: true);
        return reader.ReadToEnd();
    }

    /// <summary>一時ファイルに書いてから置き換える。置き換えが共有違反で失敗したら、短い間をおいてやり直す</summary>
    public static void WriteAllTextAtomically(string path, string text, Action<TimeSpan>? sleep = null)
    {
        var temp = path + ".tmp";
        File.WriteAllText(temp, text);
        Replace(temp, path, sleep);
    }

    /// <summary>temp を path に置き換える（共有違反なら最大 MaxAttempts 回やり直す）</summary>
    public static void Replace(string temp, string path, Action<TimeSpan>? sleep = null, Action<string, string>? move = null)
    {
        sleep ??= Thread.Sleep;
        move ??= (from, to) => File.Move(from, to, overwrite: true);
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                move(temp, path);
                return;
            }
            catch (Exception e) when (attempt < MaxAttempts && IsSharingProblem(e))
            {
                sleep(RetryDelay);
            }
        }
    }

    /// <summary>ほかのプロセスが開いているための失敗か（共有違反・ロック違反・アクセス拒否）。ファイルやフォルダがないときは違う</summary>
    public static bool IsSharingProblem(Exception e) => e switch
    {
        FileNotFoundException or DirectoryNotFoundException => false,
        UnauthorizedAccessException => true,
        // ERROR_SHARING_VIOLATION（32）・ERROR_LOCK_VIOLATION（33）
        IOException io => (io.HResult & 0xFFFF) is 32 or 33,
        _ => false,
    };
}

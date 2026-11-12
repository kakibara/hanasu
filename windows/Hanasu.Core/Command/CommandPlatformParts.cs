using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Command;

// 要件: REQ-COM-186, REQ-COM-021
// 設計判断: DEC-COM-144, DEC-COM-198
/// <summary>
/// hanasu が Windows Hello で守ったキーを読むときの確認（W3）。画面のないセッション（SSH など）では確認を出さずに断り、
/// 確認が timeout までに終わらなければ、画面がほかのウインドウの裏に隠れていないかを添えて断る。
/// 断ったときは SecretAccessException（終了コード 3。MCP は isError）
/// </summary>
public sealed class GuardedPresenceKey(IUserPresenceKey inner, Func<bool> hasDesktop, TimeSpan timeout) : IUserPresenceKey
{
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(60);

    public Task<bool> IsAvailableAsync() => inner.IsAvailableAsync();

    public async Task<byte[]> DeriveKeyAsync(bool create, CancellationToken cancellationToken)
    {
        if (!hasDesktop()) throw new SecretAccessException(Strings.Cmd_HelloNoDesktop);
        using var limit = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var derive = inner.DeriveKeyAsync(create, limit.Token);
        var finished = await Task.WhenAny(derive, Task.Delay(timeout, cancellationToken)).ConfigureAwait(false);
        if (finished != derive)
        {
            cancellationToken.ThrowIfCancellationRequested();
            limit.Cancel();
            _ = derive.ContinueWith(t => _ = t.Exception, TaskScheduler.Default);
            throw new SecretAccessException(string.Format(Strings.Cmd_HelloTimeout, (int)timeout.TotalSeconds));
        }
        return await derive.ConfigureAwait(false);
    }

    /// <summary>画面のあるセッションか（SSH で入ったとき・サービスでは false）</summary>
    public static bool DesktopAvailable(IReadOnlyDictionary<string, string> environment) =>
        System.Environment.UserInteractive
        && !environment.ContainsKey("SSH_CONNECTION") && !environment.ContainsKey("SSH_CLIENT");
}

// 要件: REQ-COM-180
// 設計判断: DEC-COM-195
/// <summary>文字コード（WD9）。パイプ・ファイルから受け取った文は UTF-8 として読み、正しくなければコンソールのコードページで読み直す</summary>
public static class CommandEncoding
{
    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    /// <summary>
    /// 受け取ったバイトを文にする。先頭の BOM は外す。UTF-8 として正しくなければ fallback（cmd の echo のように、
    /// コンソールのコードページで書く相手のため）で読み直す
    /// </summary>
    public static string DecodeInput(byte[] bytes, Encoding? fallback)
    {
        var span = bytes.AsSpan();
        if (span.StartsWith(new byte[] { 0xEF, 0xBB, 0xBF })) span = span[3..];
        try
        {
            return StrictUtf8.GetString(span);
        }
        catch (DecoderFallbackException) when (fallback is not null)
        {
            return fallback.GetString(span);
        }
        catch (DecoderFallbackException)
        {
            return new UTF8Encoding(false).GetString(span);
        }
    }

    /// <summary>パイプ・ファイルに書くバイト（UTF-8・BOM なし。改行は \n のまま）</summary>
    public static byte[] EncodeOutput(string text) => new UTF8Encoding(false).GetBytes(text);
}

// 要件: REQ-COM-191
// 設計判断: DEC-COM-199
/// <summary>
/// ユーザーの PATH（HKCU\Environment の Path）の項目の扱い（W4・WD7）。値は ; で区切った項目の並びで、%…% の書き方を含みうる。
/// 足す・外すときは、ほかの項目の書き方と並びを変えない
/// </summary>
public static class CommandPath
{
    /// <summary>項目の並び（空の項目は除く）</summary>
    public static IReadOnlyList<string> Entries(string? value) =>
        (value ?? "").Split(';').Select(e => e.Trim()).Where(e => e.Length > 0).ToList();

    /// <summary>同じフォルダを指すか（%…% を広げ、末尾の \ を除き、大文字小文字を区別しない）</summary>
    public static bool Same(string entry, string directory, Func<string, string>? expand = null)
    {
        expand ??= System.Environment.ExpandEnvironmentVariables;
        static string Normalize(string path) => path.Trim().Trim('"').TrimEnd('\\', '/');
        return string.Equals(Normalize(expand(entry)), Normalize(directory), StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>cli のフォルダを最後に足した値。すでにあればそのまま</summary>
    public static string Add(string? value, string directory, Func<string, string>? expand = null)
    {
        var current = value ?? "";
        if (Entries(current).Any(e => Same(e, directory, expand))) return current;
        if (current.Length == 0) return directory;
        return current.EndsWith(';') ? current + directory : current + ";" + directory;
    }

    /// <summary>その項目（同じフォルダを指すもの）だけを外した値。ほかの項目の書き方は変えない</summary>
    public static string Remove(string? value, string directory, Func<string, string>? expand = null)
    {
        var kept = (value ?? "").Split(';').Where(p => p.Trim().Length == 0 || !Same(p, directory, expand));
        return string.Join(";", kept);
    }

    /// <summary>
    /// PATH の状態。Others は、別の場所の Hanasu の cli を指す項目（末尾が \cli で、その親に Hanasu.exe があるか、
    /// 前に Hanasu が足したと記録した値と同じもの。消えたフォルダも、記録があれば見分ける）
    /// </summary>
    public static PathStatus Status(string? userPath, string cliDirectory, string? processPath, string? recorded,
        Func<string, bool> fileExists, Func<string, string>? expand = null)
    {
        expand ??= System.Environment.ExpandEnvironmentVariables;
        var entries = Entries(userPath);
        var current = entries.FirstOrDefault(e => Same(e, cliDirectory, expand));
        var others = entries.Where(e => !Same(e, cliDirectory, expand)).Where(e =>
        {
            var expanded = expand(e).Trim().Trim('"').TrimEnd('\\', '/');
            var isCli = expanded.EndsWith("\\cli", StringComparison.OrdinalIgnoreCase) || expanded.EndsWith("/cli", StringComparison.OrdinalIgnoreCase);
            var parent = expanded.Length > 4 ? expanded[..^4] : "";
            // Windows のパスなので、区切りは \ で組み立てる（Mac のテストでも同じ文字列になるように）
            return (isCli && fileExists(parent + "\\Hanasu.exe")) || (recorded is not null && Same(e, recorded, expand));
        }).ToList();
        var onProcessPath = Entries(processPath).Any(e => Same(e, cliDirectory, expand));
        return new PathStatus(current, others, onProcessPath);
    }

    /// <summary>実行ファイルが一時フォルダ（zip の中から開いたときなど）にあるか</summary>
    public static bool IsTemporary(string executablePath, string tempDirectory) =>
        executablePath.StartsWith(tempDirectory.TrimEnd('\\', '/') + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
        || executablePath.StartsWith(tempDirectory.TrimEnd('\\', '/') + "\\", StringComparison.OrdinalIgnoreCase);
}

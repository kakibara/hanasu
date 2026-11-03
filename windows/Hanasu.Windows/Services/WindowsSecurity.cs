using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using Hanasu.Core.Settings;
using Hanasu.Windows.Native;
using Windows.Security.Credentials;
using Windows.Security.Cryptography;

namespace Hanasu.Windows.Services;

/// <summary>
/// Windows Hello（KeyCredentialManager）の鍵で、API キーを暗号化する鍵を作る。
/// 1. 「Hanasu.ApiKeys」という名前の鍵を Windows Hello に作る（秘密鍵は TPM などに置かれ、取り出せない）
/// 2. 決まった文字列にその鍵で署名する（このとき Windows Hello の確認が出る）。RSA の PKCS#1 v1.5 の署名は、同じ鍵と同じ文字列ならいつも同じ値になる
/// 3. 署名の SHA-256 を AES-256 の鍵にする（SecretStore が AES-GCM で暗号化する）
/// 同じ Windows ユーザーで動くほかのアプリも、同じ名前の鍵で署名を求めることはできるが、そのたびに Windows Hello の確認が出る。
/// </summary>
// 要件: REQ-COM-021
// 設計判断: DEC-COM-144
internal sealed class WindowsHelloKey : IUserPresenceKey
{
    private const string CredentialName = "Hanasu.ApiKeys";
    private static readonly string Challenge = "Hanasu.Windows.SecretKey.v1";

    public async Task<bool> IsAvailableAsync()
    {
        try
        {
            return await KeyCredentialManager.IsSupportedAsync();
        }
        catch (Exception e) when (e is COMException or UnauthorizedAccessException)
        {
            AppLog.Write($"windows hello unavailable: {e.GetType().Name}");
            return false;
        }
    }

    public async Task<byte[]> DeriveKeyAsync(bool create, CancellationToken cancellationToken)
    {
        if (!await IsAvailableAsync())
        {
            throw new SecretAccessException("Windows Hello が設定されていません（Windows の設定 → アカウント → サインイン オプション で PIN などを設定してください）");
        }
        var credential = await OpenAsync(create);
        cancellationToken.ThrowIfCancellationRequested();
        // タスクトレイのアプリから呼ぶと、確認の画面が後ろに隠れることがあるので、前に出す
        using var focus = new CancellationTokenSource();
        _ = BringDialogToFrontAsync(focus.Token);
        KeyCredentialOperationResult signed;
        try
        {
            signed = await credential.RequestSignAsync(CryptographicBuffer.ConvertStringToBinary(Challenge, BinaryStringEncoding.Utf8));
        }
        finally
        {
            focus.Cancel();
        }
        if (signed.Status != KeyCredentialStatus.Success)
        {
            throw new SecretAccessException(signed.Status == KeyCredentialStatus.UserCanceled
                ? "Windows Hello の確認が取り消されたため、API キーを読めませんでした"
                : $"Windows Hello で確認できませんでした（{signed.Status}）");
        }
        CryptographicBuffer.CopyToByteArray(signed.Result, out var signature);
        try
        {
            return SHA256.HashData(signature);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(signature);
        }
    }

    private static async Task<KeyCredential> OpenAsync(bool create)
    {
        var opened = await KeyCredentialManager.OpenAsync(CredentialName);
        if (opened.Status == KeyCredentialStatus.Success) return opened.Credential;
        if (opened.Status != KeyCredentialStatus.NotFound || !create)
        {
            throw new SecretAccessException(opened.Status == KeyCredentialStatus.NotFound
                ? "Windows Hello の鍵が見つかりません（Windows Hello を設定し直した可能性があります）。設定 → AI で API キーを入れ直してください"
                : $"Windows Hello の鍵を開けませんでした（{opened.Status}）");
        }
        var created = await KeyCredentialManager.RequestCreateAsync(CredentialName, KeyCredentialCreationOption.FailIfExists);
        if (created.Status != KeyCredentialStatus.Success)
        {
            throw new SecretAccessException(created.Status == KeyCredentialStatus.UserCanceled
                ? "Windows Hello の確認が取り消されました"
                : $"Windows Hello の鍵を作れませんでした（{created.Status}）");
        }
        return created.Credential;
    }

    /// <summary>Windows Hello の確認の画面（クラス名 Credential Dialog Xaml Host）が出たら、前面に出す（最大 5 秒探す）</summary>
    private static async Task BringDialogToFrontAsync(CancellationToken cancellationToken)
    {
        for (var i = 0; i < 50 && !cancellationToken.IsCancellationRequested; i++)
        {
            var hwnd = NativeMethods.FindWindowW("Credential Dialog Xaml Host", null);
            if (hwnd != IntPtr.Zero)
            {
                NativeMethods.SetForegroundWindow(hwnd);
                return;
            }
            try { await Task.Delay(100, cancellationToken); } catch (TaskCanceledException) { return; }
        }
    }
}

// 要件: REQ-COM-022
/// <summary>Windows に特有の守り（起動の最初に呼ぶもの、入力先の確かめ）。</summary>
internal static class WindowsSecurity
{
    /// <summary>
    /// DLL を探す場所を、exe のフォルダ・System32・AddDllDirectory で足したフォルダに絞る（作業フォルダと PATH を外す）。
    /// Whisper のネイティブライブラリ（runtimes/win-*/）はそのフォルダを足しておく（依存の ggml-*.dll をそこから読むため）。
    /// exe が起動するときに読む DLL（静的なインポート）には効かない（起動したあとの LoadLibrary に効く）。
    /// </summary>
    // 設計判断: DEC-COM-148
    public static void HardenDllSearch()
    {
        try
        {
            // SetDllDirectory("") は、作業フォルダを探索から外す（古い Windows でも効く）
            NativeMethods.SetDllDirectoryW("");
            if (!NativeMethods.SetDefaultDllDirectories(NativeMethods.LOAD_LIBRARY_SEARCH_APPLICATION_DIR
                    | NativeMethods.LOAD_LIBRARY_SEARCH_SYSTEM32 | NativeMethods.LOAD_LIBRARY_SEARCH_USER_DIRS))
            {
                AppLog.Write($"SetDefaultDllDirectories failed: {Marshal.GetLastWin32Error()}");
            }
            var runtimes = Path.Combine(AppContext.BaseDirectory, "runtimes", RuntimeInformation.ProcessArchitecture == Architecture.Arm64 ? "win-arm64" : "win-x64");
            if (Directory.Exists(runtimes) && NativeMethods.AddDllDirectory(runtimes) == IntPtr.Zero)
            {
                AppLog.Write($"AddDllDirectory failed: {Marshal.GetLastWin32Error()}");
            }
        }
        catch (Exception e) when (e is EntryPointNotFoundException or DllNotFoundException)
        {
            AppLog.Write($"dll search hardening unavailable: {e.GetType().Name}");
        }
    }

    /// <summary>
    /// ウインドウのプロセスが、Hanasu より高い整合性レベル（管理者として実行など）で動いているか。
    /// そういうウインドウには SendInput のキーが届かない（UIPI）が、SendInput は成功を返すので、送る前に確かめる。
    /// 調べられないとき（トークンを開けない＝ほぼ高い権限）も true にする。
    /// </summary>
    // 設計判断: DEC-COM-149
    public static bool IsHigherIntegrity(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return false;
        NativeMethods.GetWindowThreadProcessId(hwnd, out var pid);
        if (pid == 0) return false;
        var own = IntegrityOf(NativeMethods.GetCurrentProcess(), closeProcess: false);
        var process = NativeMethods.OpenProcess(NativeMethods.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (process == IntPtr.Zero) return true;
        var target = IntegrityOf(process, closeProcess: true);
        if (own is null) return false;
        return target is null || target > own;
    }

    private static uint? IntegrityOf(IntPtr process, bool closeProcess)
    {
        var token = IntPtr.Zero;
        var buffer = IntPtr.Zero;
        try
        {
            if (!NativeMethods.OpenProcessToken(process, NativeMethods.TOKEN_QUERY, out token)) return null;
            NativeMethods.GetTokenInformation(token, NativeMethods.TokenIntegrityLevel, IntPtr.Zero, 0, out var length);
            if (length == 0) return null;
            buffer = Marshal.AllocHGlobal((int)length);
            if (!NativeMethods.GetTokenInformation(token, NativeMethods.TokenIntegrityLevel, buffer, length, out _)) return null;
            // TOKEN_MANDATORY_LABEL の先頭は SID_AND_ATTRIBUTES（Sid のポインタ）。整合性レベルは SID の最後のサブオーソリティ
            var sid = Marshal.ReadIntPtr(buffer);
            var count = Marshal.ReadByte(NativeMethods.GetSidSubAuthorityCount(sid));
            if (count == 0) return null;
            return (uint)Marshal.ReadInt32(NativeMethods.GetSidSubAuthority(sid, (uint)(count - 1)));
        }
        finally
        {
            if (buffer != IntPtr.Zero) Marshal.FreeHGlobal(buffer);
            if (token != IntPtr.Zero) NativeMethods.CloseHandle(token);
            if (closeProcess) NativeMethods.CloseHandle(process);
        }
    }
}

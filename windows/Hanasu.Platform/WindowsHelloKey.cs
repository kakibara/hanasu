using System.Runtime.InteropServices;
using System.Security.Cryptography;
using Hanasu.Core.Settings;
using Windows.Security.Credentials;
using Windows.Security.Cryptography;

namespace Hanasu.Platform;

/// <summary>
/// Windows Hello（KeyCredentialManager）の鍵で、API キーを暗号化する鍵を作る。
/// 1. 「Hanasu.ApiKeys」という名前の鍵を Windows Hello に作る（秘密鍵は TPM などに置かれ、取り出せない）
/// 2. 決まった文字列にその鍵で署名する（このとき Windows Hello の確認が出る）。RSA の PKCS#1 v1.5 の署名は、同じ鍵と同じ文字列ならいつも同じ値になる
/// 3. 署名の SHA-256 を AES-256 の鍵にする（SecretStore が AES-GCM で暗号化する）
/// 同じ Windows ユーザーで動くほかのアプリも、同じ名前の鍵で署名を求めることはできるが、そのたびに Windows Hello の確認が出る。
/// </summary>
// 要件: REQ-COM-021
// 設計判断: DEC-COM-144
public sealed class WindowsHelloKey : IUserPresenceKey
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
            throw new SecretAccessException(Strings.Hello_NotSetUp);
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
                ? Strings.Hello_CanceledCannotRead
                : string.Format(Strings.Hello_VerifyFailed, signed.Status));
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
                ? Strings.Hello_KeyNotFound
                : string.Format(Strings.Hello_OpenFailed, opened.Status));
        }
        var created = await KeyCredentialManager.RequestCreateAsync(CredentialName, KeyCredentialCreationOption.FailIfExists);
        if (created.Status != KeyCredentialStatus.Success)
        {
            throw new SecretAccessException(created.Status == KeyCredentialStatus.UserCanceled
                ? Strings.Hello_Canceled
                : string.Format(Strings.Hello_CreateFailed, created.Status));
        }
        return created.Credential;
    }

    /// <summary>Windows Hello の確認の画面（クラス名 Credential Dialog Xaml Host）が出たら、前面に出す（最大 5 秒探す）</summary>
    private static async Task BringDialogToFrontAsync(CancellationToken cancellationToken)
    {
        for (var i = 0; i < 50 && !cancellationToken.IsCancellationRequested; i++)
        {
            var hwnd = PlatformNative.FindWindowW("Credential Dialog Xaml Host", null);
            if (hwnd != IntPtr.Zero)
            {
                PlatformNative.SetForegroundWindow(hwnd);
                return;
            }
            try { await Task.Delay(100, cancellationToken); } catch (TaskCanceledException) { return; }
        }
    }
}

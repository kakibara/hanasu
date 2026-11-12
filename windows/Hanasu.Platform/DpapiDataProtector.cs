using System.Security.Cryptography;
using Hanasu.Core.Settings;

namespace Hanasu.Platform;

/// <summary>
/// DPAPI（CurrentUser）。同じ Windows ユーザーでしか復号できない（同じユーザーで動くほかのプロセスは復号できる。docs/design/security-windows.md）。
/// エントロピーは SecretStore が種類ごとに決める。
/// </summary>
// 設計判断: DEC-COM-144
public sealed class DpapiDataProtector : IDataProtector
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

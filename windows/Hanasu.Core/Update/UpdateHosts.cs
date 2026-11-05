namespace Hanasu.Core.Update;

/// <summary>
/// アップデートで通信してよい場所。API の URL はコードに固定し、ダウンロードは https の GitHub のホストだけ。
/// </summary>
// 設計判断: DEC-REL-021
public static class UpdateHosts
{
    public const string Repository = "kakibara/hanasu";
    public static readonly Uri LatestReleaseApi = new($"https://api.github.com/repos/{Repository}/releases/latest");

    private static readonly HashSet<string> Hosts = new(StringComparer.OrdinalIgnoreCase)
    {
        "github.com",
        "api.github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    };

    /// <summary>https で、github.com・api.github.com・*.githubusercontent.com のどれか</summary>
    public static bool IsAllowed(Uri? uri)
    {
        if (uri is null || !uri.IsAbsoluteUri || uri.Scheme != Uri.UriSchemeHttps) return false;
        if (!string.IsNullOrEmpty(uri.UserInfo)) return false;
        var host = uri.Host;
        return Hosts.Contains(host) || host.EndsWith(".githubusercontent.com", StringComparison.OrdinalIgnoreCase);
    }
}

using System.Text.Json;
using System.Text.RegularExpressions;

namespace Hanasu.Core.Update;

/// <summary>
/// GitHub の releases/latest の応答（JSON）から、版・リリースのページ・インストール用の zip を取り出す。
/// 下書き（draft）と先行版（prerelease）は無いものとして扱う。
/// zip は、名前がちょうど Hanasu-&lt;版&gt;-Windows-x64.zip のものだけ（Mac 版の zip や別の名前は選ばない）。
/// </summary>
// 設計判断: DEC-REL-020, DEC-REL-021
public static partial class ReleaseParser
{
    /// <summary>大きすぎる zip は受け取らない（想定の大きさは数百 MB まで）</summary>
    public const long MaxAssetBytes = 2L * 1024 * 1024 * 1024;

    [GeneratedRegex("^sha256:([0-9a-fA-F]{64})$")]
    private static partial Regex DigestPattern();

    /// <summary>タグの先頭の v を除いたものが版（v1.5.0 なら Hanasu-1.5.0-Windows-x64.zip）</summary>
    public static string AssetNameFor(string tag) => $"Hanasu-{tag.Trim().TrimStart('v', 'V')}-Windows-x64.zip";

    /// <summary>読めない・下書き・先行版・版が読めないときは null。JSON が壊れていれば UpdateException</summary>
    public static ReleaseInfo? Parse(string json)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(json);
        }
        catch (JsonException e)
        {
            throw new UpdateException("リリースの情報を読めませんでした", e);
        }
        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return null;
            if (Bool(root, "draft") || Bool(root, "prerelease")) return null;
            var tag = Str(root, "tag_name");
            var version = AppVersion.Parse(tag);
            if (version is null || tag is null) return null;

            var releaseUrl = ReleasePage(Str(root, "html_url"), tag);
            return new ReleaseInfo(version, tag, releaseUrl, Str(root, "body") ?? "", FindAsset(root, tag));
        }
    }

    private static UpdateAsset? FindAsset(JsonElement root, string tag)
    {
        if (!root.TryGetProperty("assets", out var assets) || assets.ValueKind != JsonValueKind.Array) return null;
        var wanted = AssetNameFor(tag);
        foreach (var asset in assets.EnumerateArray())
        {
            if (asset.ValueKind != JsonValueKind.Object || Str(asset, "name") != wanted) continue;
            if (!Uri.TryCreate(Str(asset, "browser_download_url"), UriKind.Absolute, out var url) || !UpdateHosts.IsAllowed(url)) return null;
            if (!asset.TryGetProperty("size", out var sizeElement) || !sizeElement.TryGetInt64(out var size) || size <= 0 || size > MaxAssetBytes) return null;
            var match = DigestPattern().Match(Str(asset, "digest") ?? "");
            if (!match.Success) return null;
            return new UpdateAsset(wanted, url, size, match.Groups[1].Value.ToUpperInvariant());
        }
        return null;
    }

    /// <summary>ブラウザで開くので、GitHub の https 以外が書かれていたら、タグから作った URL にする</summary>
    private static Uri ReleasePage(string? htmlUrl, string tag)
    {
        if (Uri.TryCreate(htmlUrl, UriKind.Absolute, out var url) && UpdateHosts.IsAllowed(url)) return url;
        return new Uri($"https://github.com/{UpdateHosts.Repository}/releases/tag/{Uri.EscapeDataString(tag)}");
    }

    private static string? Str(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static bool Bool(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.True;
}

using System.Net;
using System.Net.Http.Headers;

namespace Hanasu.Core.Update;

/// <summary>
/// 更新の確認（GitHub の API から最新のリリースを取って、今の版と比べる）と、確認の結果をユーザーに見せるかの判断。
/// </summary>
// 設計判断: DEC-REL-020, DEC-REL-022
public static class UpdateChecker
{
    /// <summary>API 用の HttpClient（リダイレクトに従わない。待ち時間は 15 秒）</summary>
    public static HttpClient CreateApiClient(string appVersion)
    {
        var http = SafeHttp.Create(TimeSpan.FromSeconds(15));
        ConfigureHeaders(http, appVersion);
        return http;
    }

    /// <summary>zip のダウンロード用の HttpClient（GitHub の CDN へのリダイレクトに従う）</summary>
    public static HttpClient CreateDownloadClient(string appVersion)
    {
        var http = SafeHttp.CreateForDownloads();
        ConfigureHeaders(http, appVersion);
        return http;
    }

    private static void ConfigureHeaders(HttpClient http, string appVersion)
    {
        http.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("Hanasu", appVersion));
        http.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
    }

    /// <summary>最新のリリースを取って、今の版と比べる。通信や応答に問題があれば UpdateException</summary>
    public static async Task<UpdateCheckResult> CheckAsync(HttpClient http, AppVersion current, CancellationToken cancellationToken)
    {
        string json;
        try
        {
            using var response = await http.GetAsync(UpdateHosts.LatestReleaseApi, cancellationToken).ConfigureAwait(false);
            if (response.StatusCode == HttpStatusCode.NotFound) return Evaluate(null, current);
            if (!response.IsSuccessStatusCode)
            {
                var hint = response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.TooManyRequests ? "（GitHub の呼び出しの上限に達したかもしれません。しばらくしてからもう一度試してください）" : "";
                throw new UpdateException($"GitHub から最新の版を取れませんでした（HTTP {(int)response.StatusCode}）{hint}");
            }
            json = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (HttpRequestException e)
        {
            throw new UpdateException($"GitHub に接続できませんでした: {e.Message}", e);
        }
        catch (TaskCanceledException e) when (!cancellationToken.IsCancellationRequested)
        {
            throw new UpdateException("GitHub からの応答が時間内に返りませんでした", e);
        }
        return Evaluate(ReleaseParser.Parse(json), current);
    }

    /// <summary>リリースと今の版から結果を決める。リリースが無い（null）・今の版以下なら最新</summary>
    public static UpdateCheckResult Evaluate(ReleaseInfo? release, AppVersion current)
    {
        if (release is null || release.Version <= current) return new UpdateCheckResult(UpdateCheckKind.UpToDate, current, release);
        return new UpdateCheckResult(release.Asset is null ? UpdateCheckKind.AvailableWithoutInstaller : UpdateCheckKind.Available, current, release);
    }

    /// <summary>
    /// 見つかった更新をユーザーに知らせるか。起動時の確認（manual = false）は、スキップした版を知らせない。
    /// 手動の確認（manual = true）はスキップを無視する。スキップは、その版だけに効く（もっと新しい版は知らせる）
    /// </summary>
    public static bool ShouldPrompt(UpdateCheckResult result, string skippedVersion, bool manual)
    {
        if (!result.HasUpdate || result.Release is null) return false;
        if (manual) return true;
        var skipped = AppVersion.Parse(skippedVersion);
        return skipped is null || !skipped.Equals(result.Release.Version);
    }

    /// <summary>zip をダウンロードして、大きさと SHA-256 を確かめてから destinationPath に置く（ホストはアップデート用の許可リスト）</summary>
    public static Task DownloadAsync(HttpClient http, UpdateAsset asset, string destinationPath, Action<long, long>? progress, CancellationToken cancellationToken) =>
        ModelDownload.DownloadVerifiedAsync(http, asset.DownloadUrl, destinationPath, asset.Sha256, asset.Size, progress,
            UpdateHosts.IsAllowed, UpdateHosts.IsAllowed, cancellationToken);
}

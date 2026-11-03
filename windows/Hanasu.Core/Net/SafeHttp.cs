namespace Hanasu.Core;

/// <summary>
/// API（Gemini・Claude）とモデルのダウンロードに使う HttpClient を作る。
/// </summary>
// 設計判断: DEC-COM-145
public static class SafeHttp
{
    /// <summary>
    /// API 用。リダイレクトに従わない（API キーを独自のヘッダーで送るので、別のホストへ付いていかないようにする）。
    /// 証明書は OS の検証に任せる（検証を外す設定はどこにも置かない）。タイムアウトは呼ぶ側で決める（既定は無限）
    /// </summary>
    public static HttpClient Create(TimeSpan? timeout = null) =>
        new(new SocketsHttpHandler
        {
            AllowAutoRedirect = false,
            // 長く使い回す HttpClient でも、DNS の変化に追従する
            PooledConnectionLifetime = TimeSpan.FromMinutes(10),
        })
        {
            Timeout = timeout ?? System.Threading.Timeout.InfiniteTimeSpan,
        };

    /// <summary>
    /// モデルのダウンロード用。Hugging Face・GitHub は CDN へリダイレクトするので従うが、https から http へは .NET が従わない。
    /// 秘密のヘッダーは付けない。中身はハッシュで確かめる（ModelDownload）
    /// </summary>
    public static HttpClient CreateForDownloads(TimeSpan? timeout = null) =>
        new(new SocketsHttpHandler { AllowAutoRedirect = true, MaxAutomaticRedirections = 5 })
        {
            Timeout = timeout ?? System.Threading.Timeout.InfiniteTimeSpan,
        };
}

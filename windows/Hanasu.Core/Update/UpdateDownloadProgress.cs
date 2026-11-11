namespace Hanasu.Core.Update;

/// <summary>
/// アップデートの zip のダウンロードの進み具合の計算（窓に出す割合と、出すかの間引き）。
/// 全体はリリースの API の size を使う。Mac の UpdateProgressModel と同じ決まり
/// </summary>
// 要件: REQ-REL-012
// 設計判断: DEC-REL-028
public static class UpdateDownloadProgress
{
    /// <summary>画面を更新する最短の間</summary>
    public static readonly TimeSpan MinInterval = TimeSpan.FromSeconds(0.1);

    /// <summary>0〜1（全体を超えない。全体が 0 以下なら 0）</summary>
    public static double Fraction(long received, long total) =>
        total <= 0 ? 0 : Math.Clamp((double)received / total, 0, 1);

    /// <summary>切り捨てた整数の %（0〜100）</summary>
    public static int Percent(long received, long total) =>
        total <= 0 ? 0 : (int)Math.Clamp(received * 100 / total, 0, 100);

    /// <summary>
    /// 画面に出すか: 前に出してから 0.1 秒以上たち、かつ落とした量が変わったとき。全体に達したときは必ず出す。
    /// lastPublishedAt が null なら、まだ一度も出していない
    /// </summary>
    public static bool ShouldPublish(DateTime? lastPublishedAt, long lastReceived, DateTime now, long received, long total)
    {
        if (received == lastReceived) return false;
        if (received >= total) return true;
        if (lastPublishedAt is not { } last) return true;
        return now - last >= MinInterval;
    }
}

using Hanasu.Core.Ai;

namespace Hanasu.Core.Claude;

/// <summary>Claude のモデル 1 つ。Id は API に送る文字列（日付を付けない）</summary>
public sealed record ClaudeModelInfo(string Id, string Label, bool SupportsServerSideFallback);

/// <summary>
/// 選べる Claude のモデルと、文章の処理の種類ごとの送り方（effort・出力の上限）。
/// </summary>
// 要件: REQ-COM-023
// 設計判断: DEC-COM-141, DEC-COM-142
public static class ClaudeModels
{
    /// <summary>音声入力（整形・英訳）の既定のモデル（ユーザーの指示「規定モデルは haiku にして」。REQ-COM-023）</summary>
    public const string DefaultModel = "claude-haiku-5-5";

    /// <summary>会議（議事録）の既定のモデル（ユーザーの指示「Claude は議事録は sonnet にして」。REQ-COM-023）</summary>
    public const string DefaultMinutesModel = "claude-sonnet-5-5";

    public static readonly IReadOnlyList<ClaudeModelInfo> All =
    [
        // Haiku 5.5 にはサーバー側の fallbacks がない（"default" は断られたまま、一覧を送ると 400）
        new(DefaultModel, "Claude Haiku 5.5（速い・安い。音声入力の既定）", SupportsServerSideFallback: false),
        new(DefaultMinutesModel, "Claude Sonnet 5.5（議事録の既定）", SupportsServerSideFallback: true),
        new("claude-opus-5-5", "Claude Opus 5.5（いちばん賢い・高い）", SupportsServerSideFallback: true),
    ];

    public static ClaudeModelInfo? Find(string? id) =>
        All.FirstOrDefault(m => string.Equals(m.Id, id?.Trim(), StringComparison.Ordinal));

    /// <summary>一覧にないモデル ID は既定に戻す（設定ファイルを手で書き換えた、古い ID が残った など）</summary>
    public static string Normalize(string? id, string fallback = DefaultModel) => Find(id)?.Id ?? fallback;

    /// <summary>
    /// 考える量。整形・英訳は軽い処理なので low（待ち時間を短くする）、議事録は medium（明示する。Sonnet 5.5 の既定は high、
    /// Haiku 5.5・Opus 5.5 の既定は medium で、モデルで違うため）。
    /// thinking は送らない（3 つのモデルとも既定で adaptive。Opus 5.5 は止められず、Sonnet 5.5 は disabled が 400 になる）
    /// </summary>
    public static string Effort(TextPurpose purpose) => purpose == TextPurpose.Minutes ? "medium" : "low";

    /// <summary>出力の上限。thinking も数に入るので、返す文章より大きめにする（議事録は長いので 32,000。待ち時間は呼ぶ側で 5 分にする）</summary>
    public static int MaxTokens(TextPurpose purpose) => purpose == TextPurpose.Minutes ? 32_000 : 8_000;
}

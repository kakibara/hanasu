namespace Hanasu.Core.LocalLlm;

/// <summary>サンプリングの設定（null の項目は送らない）</summary>
public sealed record LocalLlmSampling(double Temperature, double? TopP, int? TopK, double? RepeatPenalty);

/// <summary>
/// 端末の中で動かす小型の LLM（ローカル）。版（Hugging Face のコミット）・ファイル・大きさ・SHA-256 を決めておき、
/// 設定からダウンロードしたものだけを使う。Mac 版の LocalLLMModel.swift と同じ値にする（両方を直す）
/// </summary>
// 要件: REQ-COM-030
// 設計判断: DEC-COM-062, DEC-COM-064, DEC-COM-066, DEC-COM-067
public sealed record LocalLlmModel(
    string Id,
    string Name,
    string Summary,
    string Repository,
    string Revision,
    string FileName,
    long Bytes,
    string Sha256,
    int ContextLength,
    LocalLlmSampling Sampling,
    string License,
    string LicenseUrl)
{
    public static readonly LocalLlmModel Gemma4E4B = new(
        "gemma-4-e4b", "Gemma 4 E4B", "おすすめ。Google。いちばん大きく、整形も議事録もいちばん自然。メモリ 16 GB 以上向け",
        "ggml-org/gemma-4-E4B-it-GGUF", "a69f018d7678a2b9f5e705f8903d6fb29b9b25dc", "gemma-4-E4B-it-Q4_0.gguf",
        4_590_807_392, "a555b900214b477d8880e7832e0b8925e139b0159640036b09fe472b6f2097f2",
        32_768, new LocalLlmSampling(1.0, 0.95, 64, null),
        "Apache-2.0", "https://huggingface.co/google/gemma-4-E4B-it");

    public static readonly LocalLlmModel Lfm25JP = new(
        "lfm2.5-1.2b-jp", "LFM2.5-1.2B-JP", "Liquid AI。小さく速い。日本語の指示に強い",
        "LiquidAI/LFM2.5-1.2B-JP-202606-GGUF", "448ba3f7d408c2f5c32cec8038612f7c1ed9f054", "LFM2.5-1.2B-JP-202606-Q8_0.gguf",
        1_246_253_344, "d61784727aeac0da2f413dbb481273f465c7adf01b0bd72c8fd2ca1040c62c5e",
        32_768, new LocalLlmSampling(0.1, null, 50, 1.05),
        "LFM Open License v1.0", "https://huggingface.co/LiquidAI/LFM2.5-1.2B-JP-202606/blob/main/LICENSE");

    public static readonly LocalLlmModel Sarashina22 = new(
        "sarashina2.2-3b", "Sarashina2.2（3B）", "SB Intuitions。日本語で学習。文脈は 8K まで（長い会議は分けてまとめる）",
        "mmnga/sarashina2.2-3b-instruct-v0.1-gguf", "31d771319b04032f33e0d9d860f3984ea4812154", "sarashina2.2-3b-instruct-v0.1-Q4_K_M.gguf",
        2_066_390_112, "d96f4d98eb528df26e8bc09ab81a1d165be4fce67616739e65980bed9038f0f2",
        8_192, new LocalLlmSampling(0.2, 0.95, null, 1.05),
        "MIT", "https://huggingface.co/sbintuitions/sarashina2.2-3b-instruct-v0.1");

    // Qwen3.5 の推奨の presence_penalty 2.0 は、元の言葉を残す整形で語を避けさせてしまうので付けない
    public static readonly LocalLlmModel Qwen35Small = new(
        "qwen3.5-0.8b", "Qwen3.5-0.8B", "Alibaba。いちばん小さく軽い（0.8B）。メモリの少ない PC 向け。質は控えめ",
        "ggml-org/Qwen3.5-0.8B-GGUF", "807dfd9a6fadbf703207aac3bfb0b2b3040d077c", "Qwen3.5-0.8B-Q8_0.gguf",
        833_592_096, "37ae482d336108d23516fa35e8e0c4126688d81018b87178a18d752a1357814f",
        32_768, new LocalLlmSampling(1.0, 1.0, 20, null),
        "Apache-2.0", "https://huggingface.co/Qwen/Qwen3.5-0.8B");

    public static readonly IReadOnlyList<LocalLlmModel> All = [Gemma4E4B, Lfm25JP, Sarashina22, Qwen35Small];

    /// <summary>
    /// おすすめのモデル（DEC-COM-067）。実機で比べると、Sarashina2.2 と LFM2.5 は整形で言っていない文を足したり、
    /// 議事録で担当者を取り違えたり同じ議題を繰り返したりして、使い物にならなかった（docs/verification/dictation.md の 13）。
    /// Gemma 4 E4B（Google）だけが整形も議事録も安定していたので、これを勧め、音声入力・会議とも既定にする
    /// </summary>
    public static readonly LocalLlmModel Recommended = Gemma4E4B;

    /// <summary>用途の AI を初めてローカルにしたときのモデル（DEC-COM-067）</summary>
    public static readonly LocalLlmModel DefaultDictation = Recommended;
    public static readonly LocalLlmModel DefaultMeeting = Recommended;

    public bool IsRecommended => Id == Recommended.Id;

    public static LocalLlmModel? Find(string? id) => All.FirstOrDefault(m => m.Id == id);

    public Uri DownloadUri => new($"https://huggingface.co/{Repository}/resolve/{Revision}/{FileName}");

    /// <summary>ライセンスの注意（選ぶ欄に出す）</summary>
    public string LicenseNote => Id == Lfm25JP.Id
        ? $"ライセンス: {License}。年間売上 1,000 万ドル以上の組織の商用利用は、このライセンスでは許されていません"
        : $"ライセンス: {License}";

    public string SizeLabel => $"{Bytes / 1_000_000_000.0:0.00} GB";

    /// <summary>選ぶ欄に出す名前</summary>
    public string Label => $"{Name}（{SizeLabel}）{(IsRecommended ? "・おすすめ" : "")}";

    /// <summary>出力の上限。文脈の半分を超えない（DEC-COM-064）</summary>
    public int MaxOutputTokens(bool longOutput) => Math.Min(longOutput ? 4096 : 2048, ContextLength / 2);
}

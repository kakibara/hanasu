import Foundation

// 要件: REQ-COM-030
// 設計判断: DEC-COM-062, DEC-COM-064, DEC-COM-066, DEC-COM-067
/// 端末の中で動かす小型の LLM（ローカル）。版（Hugging Face のコミット）・ファイル・大きさ・SHA-256 を決めておき、
/// 設定からダウンロードしたものだけを使う（LocalLLMStore）。Windows 版の LocalLlmModel.cs と同じ値にする（両方を直す）
enum LocalLLMModel: String, CaseIterable, Identifiable, Sendable {
    case gemma4E4B = "gemma-4-e4b"
    case lfm25JP = "lfm2.5-1.2b-jp"
    case sarashina22 = "sarashina2.2-3b"
    case qwen35 = "qwen3.5-4b"

    /// おすすめのモデル（DEC-COM-067）。実機で比べると、Sarashina2.2 と LFM2.5 は整形で言っていない文を足したり、
    /// 議事録で担当者を取り違えたり同じ議題を繰り返したりして、使い物にならなかった（docs/verification/dictation.md の 13）。
    /// Qwen3.5-4B も、整形で言い直しの前の文を残し、議事録でアクションアイテムをまとめてしまった（同じく 19）。
    /// Gemma 4 E4B（Google）だけが整形も議事録も安定していたので、これを勧め、音声入力・会議とも既定にする
    static let recommended = LocalLLMModel.gemma4E4B

    /// 用途の AI を初めてローカルにしたときのモデル（DEC-COM-067）
    static let defaultDictation = recommended
    static let defaultMeeting = recommended

    var isRecommended: Bool { self == Self.recommended }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .gemma4E4B: "Gemma 4 E4B"
        case .lfm25JP: "LFM2.5-1.2B-JP"
        case .sarashina22: tr("%@（%@）", "Sarashina2.2", "3B")
        case .qwen35: "Qwen3.5-4B"
        }
    }

    /// 選ぶ欄に出す説明
    var summary: String {
        switch self {
        case .gemma4E4B: tr("おすすめ。Google。いちばん大きく、整形も議事録もいちばん自然。メモリ 16 GB 以上向け")
        case .lfm25JP: tr("Liquid AI。小さく速い。日本語の指示に強い")
        case .sarashina22: tr("SB Intuitions。日本語で学習。文脈は 8K まで（長い会議は分けてまとめる）")
        case .qwen35: tr("Alibaba。Gemma の半分ほどの大きさで、メモリが 8 GB の Mac でも動かしやすい。言い直しの扱いは Gemma より弱い")
        }
    }

    var repository: String {
        switch self {
        case .gemma4E4B: "ggml-org/gemma-4-E4B-it-GGUF"
        case .lfm25JP: "LiquidAI/LFM2.5-1.2B-JP-202606-GGUF"
        case .sarashina22: "mmnga/sarashina2.2-3b-instruct-v0.1-gguf"
        case .qwen35: "unsloth/Qwen3.5-4B-GGUF"
        }
    }

    /// Hugging Face のリポジトリのコミット。main ではなくこの版を取る
    var revision: String {
        switch self {
        case .gemma4E4B: "a69f018d7678a2b9f5e705f8903d6fb29b9b25dc"
        case .lfm25JP: "448ba3f7d408c2f5c32cec8038612f7c1ed9f054"
        case .sarashina22: "31d771319b04032f33e0d9d860f3984ea4812154"
        case .qwen35: "e87f176479d0855a907a41277aca2f8ee7a09523"
        }
    }

    var fileName: String {
        switch self {
        case .gemma4E4B: "gemma-4-E4B-it-Q4_0.gguf"
        case .lfm25JP: "LFM2.5-1.2B-JP-202606-Q8_0.gguf"
        case .sarashina22: "sarashina2.2-3b-instruct-v0.1-Q4_K_M.gguf"
        case .qwen35: "Qwen3.5-4B-Q4_K_M.gguf"
        }
    }

    var byteCount: Int64 {
        switch self {
        case .gemma4E4B: 4_590_807_392
        case .lfm25JP: 1_246_253_344
        case .sarashina22: 2_066_390_112
        case .qwen35: 2_740_937_888
        }
    }

    var sha256: String {
        switch self {
        case .gemma4E4B: "a555b900214b477d8880e7832e0b8925e139b0159640036b09fe472b6f2097f2"
        case .lfm25JP: "d61784727aeac0da2f413dbb481273f465c7adf01b0bd72c8fd2ca1040c62c5e"
        case .sarashina22: "d96f4d98eb528df26e8bc09ab81a1d165be4fce67616739e65980bed9038f0f2"
        case .qwen35: "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4"
        }
    }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(fileName)")!
    }

    /// llama-server の文脈の長さ（-c）。KV キャッシュのメモリを抑えるため、モデルの上限より小さくすることがある
    var contextLength: Int {
        switch self {
        case .gemma4E4B, .lfm25JP, .qwen35: 32_768
        case .sarashina22: 8_192
        }
    }

    struct Sampling: Sendable {
        var temperature: Double
        var topP: Double?
        var topK: Int?
        var repeatPenalty: Double?
    }

    /// 開発元の推奨（Sarashina2.2 は推奨がないので、言い換えの幅を小さくする値。
    /// Qwen3.5 の推奨の presence_penalty 1.5 は、元の言葉を残す整形で語を避けさせてしまうので付けない）
    var sampling: Sampling {
        switch self {
        case .gemma4E4B: Sampling(temperature: 1.0, topP: 0.95, topK: 64, repeatPenalty: nil)
        case .lfm25JP: Sampling(temperature: 0.1, topP: nil, topK: 50, repeatPenalty: 1.05)
        case .sarashina22: Sampling(temperature: 0.2, topP: 0.95, topK: nil, repeatPenalty: 1.05)
        case .qwen35: Sampling(temperature: 0.7, topP: 0.8, topK: 20, repeatPenalty: nil)
        }
    }

    var license: String {
        switch self {
        case .gemma4E4B, .qwen35: "Apache-2.0"
        case .lfm25JP: "LFM Open License v1.0"
        case .sarashina22: "MIT"
        }
    }

    var licenseURL: URL {
        switch self {
        case .gemma4E4B: URL(string: "https://huggingface.co/google/gemma-4-E4B-it")!
        case .lfm25JP: URL(string: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-JP-202606/blob/main/LICENSE")!
        case .sarashina22: URL(string: "https://huggingface.co/sbintuitions/sarashina2.2-3b-instruct-v0.1")!
        case .qwen35: URL(string: "https://huggingface.co/Qwen/Qwen3.5-4B")!
        }
    }

    /// ライセンスの注意（選ぶ欄に出す）
    var licenseNote: String {
        switch self {
        case .lfm25JP:
            tr("ライセンス: %@。年間売上 1,000 万ドル以上の組織の商用利用は、このライセンスでは許されていません", "\(license)")
        default:
            tr("ライセンス: %@", "\(license)")
        }
    }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

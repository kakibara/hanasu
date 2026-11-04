import Foundation

// 要件: REQ-COM-030
// 設計判断: DEC-COM-062, DEC-COM-064, DEC-COM-066, DEC-COM-067
/// 端末の中で動かす小型の LLM（ローカル）。版（Hugging Face のコミット）・ファイル・大きさ・SHA-256 を決めておき、
/// 設定からダウンロードしたものだけを使う（LocalLLMStore）。Windows 版の LocalLlmModel.cs と同じ値にする（両方を直す）
enum LocalLLMModel: String, CaseIterable, Identifiable, Sendable {
    case gemma4E4B = "gemma-4-e4b"
    case lfm25JP = "lfm2.5-1.2b-jp"
    case sarashina22 = "sarashina2.2-3b"

    /// 用途の AI を初めてローカルにしたときのモデル（DEC-COM-067）
    static let defaultDictation = LocalLLMModel.lfm25JP
    static let defaultMeeting = LocalLLMModel.gemma4E4B

    var id: String { rawValue }

    var name: String {
        switch self {
        case .gemma4E4B: "Gemma 4 E4B"
        case .lfm25JP: "LFM2.5-1.2B-JP"
        case .sarashina22: "Sarashina2.2（3B）"
        }
    }

    /// 選ぶ欄に出す説明
    var summary: String {
        switch self {
        case .gemma4E4B: "Google。いちばん大きく、長い会議もまとめやすい。メモリ 16 GB 以上向け"
        case .lfm25JP: "Liquid AI。小さく速い。日本語の指示に強い"
        case .sarashina22: "SB Intuitions。日本語で学習。文脈は 8K まで（長い会議は分けてまとめる）"
        }
    }

    var repository: String {
        switch self {
        case .gemma4E4B: "ggml-org/gemma-4-E4B-it-GGUF"
        case .lfm25JP: "LiquidAI/LFM2.5-1.2B-JP-202606-GGUF"
        case .sarashina22: "mmnga/sarashina2.2-3b-instruct-v0.1-gguf"
        }
    }

    /// Hugging Face のリポジトリのコミット。main ではなくこの版を取る
    var revision: String {
        switch self {
        case .gemma4E4B: "a69f018d7678a2b9f5e705f8903d6fb29b9b25dc"
        case .lfm25JP: "448ba3f7d408c2f5c32cec8038612f7c1ed9f054"
        case .sarashina22: "31d771319b04032f33e0d9d860f3984ea4812154"
        }
    }

    var fileName: String {
        switch self {
        case .gemma4E4B: "gemma-4-E4B-it-Q4_0.gguf"
        case .lfm25JP: "LFM2.5-1.2B-JP-202606-Q8_0.gguf"
        case .sarashina22: "sarashina2.2-3b-instruct-v0.1-Q4_K_M.gguf"
        }
    }

    var byteCount: Int64 {
        switch self {
        case .gemma4E4B: 4_590_807_392
        case .lfm25JP: 1_246_253_344
        case .sarashina22: 2_066_390_112
        }
    }

    var sha256: String {
        switch self {
        case .gemma4E4B: "a555b900214b477d8880e7832e0b8925e139b0159640036b09fe472b6f2097f2"
        case .lfm25JP: "d61784727aeac0da2f413dbb481273f465c7adf01b0bd72c8fd2ca1040c62c5e"
        case .sarashina22: "d96f4d98eb528df26e8bc09ab81a1d165be4fce67616739e65980bed9038f0f2"
        }
    }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(fileName)")!
    }

    /// llama-server の文脈の長さ（-c）。KV キャッシュのメモリを抑えるため、モデルの上限より小さくすることがある
    var contextLength: Int {
        switch self {
        case .gemma4E4B, .lfm25JP: 32_768
        case .sarashina22: 8_192
        }
    }

    struct Sampling: Sendable {
        var temperature: Double
        var topP: Double?
        var topK: Int?
        var repeatPenalty: Double?
    }

    /// 開発元の推奨（Sarashina2.2 は推奨がないので、言い換えの幅を小さくする値）
    var sampling: Sampling {
        switch self {
        case .gemma4E4B: Sampling(temperature: 1.0, topP: 0.95, topK: 64, repeatPenalty: nil)
        case .lfm25JP: Sampling(temperature: 0.1, topP: nil, topK: 50, repeatPenalty: 1.05)
        case .sarashina22: Sampling(temperature: 0.2, topP: 0.95, topK: nil, repeatPenalty: 1.05)
        }
    }

    var license: String {
        switch self {
        case .gemma4E4B: "Apache-2.0"
        case .lfm25JP: "LFM Open License v1.0"
        case .sarashina22: "MIT"
        }
    }

    var licenseURL: URL {
        switch self {
        case .gemma4E4B: URL(string: "https://huggingface.co/google/gemma-4-E4B-it")!
        case .lfm25JP: URL(string: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-JP-202606/blob/main/LICENSE")!
        case .sarashina22: URL(string: "https://huggingface.co/sbintuitions/sarashina2.2-3b-instruct-v0.1")!
        }
    }

    /// ライセンスの注意（選ぶ欄に出す）
    var licenseNote: String {
        switch self {
        case .lfm25JP:
            "ライセンス: \(license)。年間売上 1,000 万ドル以上の組織の商用利用は、このライセンスでは許されていません"
        default:
            "ライセンス: \(license)"
        }
    }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

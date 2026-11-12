import Foundation

// スニペット: 決まった言葉（起動フレーズ）を話すと、登録した文章（本文）をそのまま入力する。
// 照合は決定的に行い、Gemini には任せない。本文は Gemini に送らない。

/// 起動フレーズと本文の組。
struct Snippet: Codable, Identifiable, Equatable {
    var id: UUID
    /// 起動フレーズ。「、」か「,」で区切ると、別の言い方も同じ本文に結び付けられる（例: 「会議URL、会議のリンク」）
    var trigger: String
    var body: String

    init(id: UUID = UUID(), trigger: String, body: String) {
        self.id = id
        self.trigger = trigger
        self.body = body
    }

    /// id のない JSON（CLI の --snippets など）も読めるようにする
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        trigger = try container.decode(String.self, forKey: .trigger)
        body = try container.decode(String.self, forKey: .body)
    }

    /// 起動フレーズを区切ったもの（空は除く）
    var phrases: [String] {
        trigger.split(whereSeparator: { "、,，".contains($0) })  // skip-tr（照らし合わせ・区切りに使う記号）
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// HUD や一覧に出す名前（最初の起動フレーズ）
    var displayName: String { phrases.first ?? "" }
}

// 要件: REQ-DIC-030
// 設計判断: DEC-DIC-055
/// スニペットの一覧。UserDefaults に JSON で保存する（AppSettings とは別のキー）。
final class SnippetStore: ObservableObject {
    static let shared = SnippetStore(defaults: .standard)

    @Published var snippets: [Snippet] {
        didSet { save() }
    }
    private let defaults: UserDefaults?
    private static let key = "snippets"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([Snippet].self, from: data)
        {
            snippets = decoded
        } else {
            snippets = []
        }
    }

    /// 保存しない一覧（CLI や画面の描き出し用）
    init(snippets: [Snippet]) {
        defaults = nil
        self.snippets = snippets
    }

    /// 音声認識のヒント（contextualStrings）に足す起動フレーズ
    var triggerPhrases: [String] { snippets.flatMap(\.phrases) }

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(snippets) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// CLI と画面の描き出しで使う例（架空の内容）
    static let samples: [Snippet] = [
        Snippet(trigger: tr("メールの署名、署名"), body: tr("""
            --
            山田 太郎
            株式会社サンプル 開発部
            taro.yamada@example.com
            """)),
        Snippet(trigger: tr("自己紹介"), body: tr("はじめまして、株式会社サンプルの山田です。社内向けの業務アプリの開発を担当しています。")),
        Snippet(trigger: tr("住所"), body: tr("〒100-0000 東京都千代田区サンプル町1-2-3 サンプルビル5階")),
        Snippet(trigger: tr("会議URL、会議のリンク"), body: "https://meet.example.com/abc-defg-hij"),
    ]
}

/// 照合の結果。文字起こしを「文」と「スニペット」の並びに分けたもの。
struct SnippetMatch {
    enum Part {
        case text(String)
        case snippet(Snippet)
    }

    var parts: [Part]

    /// 話した内容の全体が起動フレーズだった（Gemini を呼ばない）
    var isWholeUtterance: Bool {
        parts.allSatisfy { if case .snippet = $0 { true } else { false } }
    }

    var snippets: [Snippet] {
        parts.compactMap { if case .snippet(let s) = $0 { s } else { nil } }
    }

    // 設計判断: DEC-DIC-052
    /// HUD の表示。例: 「スニペット『メールの署名』を入力しました」
    var hudMessage: String {
        tr("スニペット%@を入力しました", snippets.map { tr("『%@』", $0.displayName) }.joined(separator: UILanguage.current == .ja ? "" : tr("、")))
    }

    /// 文の部分をそのまま使ってつないだもの（整形しないとき・Gemini が失敗したとき）
    var assembledWithoutConversion: String {
        Self.join(parts.map { part in
            switch part {
            case .text(let text): (text, false)
            case .snippet(let s): (s.body, true)
            }
        })
    }

    // 設計判断: DEC-DIC-053, DEC-DIC-054
    /// 文の部分を convert（Gemini の整形・英訳）で変換し、スニペットの本文とつなぐ。
    /// 本文は convert に渡さない（英訳モードでも本文は訳さない）。文の部分が複数あれば並行して変換する。
    func assemble(convert: @escaping @Sendable (String) async throws -> String) async throws -> String {
        let texts: [(Int, String)] = parts.enumerated().compactMap { index, part in
            if case .text(let text) = part { (index, text) } else { nil }
        }
        let converted = try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, text) in texts {
                group.addTask { (index, try await convert(text)) }
            }
            var results: [Int: String] = [:]
            for try await (index, output) in group { results[index] = output }
            return results
        }
        return Self.join(parts.enumerated().map { index, part in
            switch part {
            case .text(let text): (converted[index] ?? text, false)
            case .snippet(let s): (s.body, true)
            }
        })
    }

    // 設計判断: DEC-DIC-053
    /// 文とスニペットをつなぐ。複数行の本文は前後で改行し、1 行の本文はそのまま続ける。
    /// 空白で語を区切る文字どうしが接するとき（英訳した文と URL、韓国語の文とスニペットなど）は半角スペースを入れる（DEC-COM-174）。
    /// 英字・数字・記号どうし（ASCII の空白以外）が接するか。前からの決まりで、「.NET」のように記号で始まるスニペットの前にも空白を入れる
    private static func asciiTouch(_ a: String, _ b: String) -> Bool {
        guard let last = a.last, let first = b.first else { return false }
        return last.isASCII && first.isASCII && !last.isWhitespace && !first.isWhitespace
    }

    static func join(_ pieces: [(text: String, isSnippet: Bool)]) -> String {
        var result = ""
        var previousIsMultilineSnippet = false
        for piece in pieces where !piece.text.isEmpty {
            let isMultilineSnippet = piece.isSnippet && piece.text.contains(where: \.isNewline)
            if !result.isEmpty {
                if previousIsMultilineSnippet || isMultilineSnippet {
                    if !result.hasSuffix("\n"), !piece.text.hasPrefix("\n") { result += "\n" }
                } else if TextSpacing.needsSpace(result, piece.text) || Self.asciiTouch(result, piece.text) {
                    result += " "
                }
            }
            result += piece.text
            previousIsMultilineSnippet = isMultilineSnippet
        }
        return result
    }
}

// 要件: REQ-DIC-030
// 設計判断: DEC-DIC-050
/// 文字起こしと起動フレーズを照合する。
enum SnippetMatcher {
    /// 文頭のフィラー（正規化した形）。長いものから順に試す
    static let leadingFillers = ["えーと", "ええと", "えっと", "あのー", "うーん", "えー", "んー"]  // skip-tr（言語の決まりに使う語。FUT-014）
    /// 文末の言い回し（正規化した形）。長いものから順に試す。
    /// 「〜をお願いします」「〜を入力して」は相手に頼む文（「自己紹介をお願いします」）と区別できないので含めない
    static let trailingSuffixes = ["ですね", "ですよ", "でした", "です"]  // skip-tr（言語の決まりに使う語。FUT-014）

    private static let removedCharacters = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)

    // 設計判断: DEC-DIC-051
    /// 表記の揺れをならす。全角・半角をそろえ（NFKC）、英字を小文字に、カタカナをひらがなにして、空白・句読点・記号を除く。
    /// 起動フレーズと文字起こしの両方にかける。
    static func normalize(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping.lowercased()
        var scalars = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars where !removedCharacters.contains(scalar) {
            // カタカナ（ァ〜ヶ）をひらがなにする。長音符「ー」はそのまま残す
            if (0x30A1...0x30F6).contains(scalar.value), let hiragana = Unicode.Scalar(scalar.value - 0x60) {
                scalars.append(hiragana)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    // 設計判断: DEC-DIC-051
    /// 文字起こし側の照合に使う形。正規化した形に加えて、文頭のフィラーと文末の「です」などを 1 つずつ外した形も試す。
    /// 起動フレーズ側からは外さない（「よろしくお願いします」を起動フレーズにしても、その形のまま一致させるため）。
    static func candidates(_ text: String) -> [String] {
        let core = normalize(text)
        var forms = [core]
        if let filler = leadingFillers.first(where: { core.hasPrefix($0) && core.count > $0.count }) {
            forms.append(String(core.dropFirst(filler.count)))
        }
        for form in forms {
            if let suffix = trailingSuffixes.first(where: { form.hasSuffix($0) && form.count > $0.count }) {
                forms.append(String(form.dropLast(suffix.count)))
            }
        }
        var seen = Set<String>()
        return forms.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // 設計判断: DEC-DIC-055
    /// 正規化した起動フレーズ → スニペット。同じ形が重なったら一覧で先のものを使う。本文が空のものは除く
    static func table(for snippets: [Snippet]) -> [String: Snippet] {
        var table: [String: Snippet] = [:]
        for snippet in snippets where !snippet.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for phrase in snippet.phrases {
                let key = normalize(phrase)
                if !key.isEmpty, table[key] == nil { table[key] = snippet }
            }
        }
        return table
    }

    // 設計判断: DEC-DIC-053
    /// 照合する。一致しなければ nil。
    /// 1. 全体が起動フレーズなら、そのスニペットだけを返す。
    /// 2. そうでなければ、句読点・空白で区切った区間（連続する複数の区間も可）が起動フレーズと一致する所を本文に置き換える。
    ///    区切りの途中では一致させない（「住所を教えてください」の「住所」は置き換えない）。
    static func match(_ transcript: String, snippets: [Snippet]) -> SnippetMatch? {
        let table = table(for: snippets)
        guard !table.isEmpty else { return nil }
        func lookup(_ text: Substring) -> Snippet? {
            candidates(String(text)).lazy.compactMap { table[$0] }.first
        }

        if let snippet = lookup(transcript[...]) {
            return SnippetMatch(parts: [.snippet(snippet)])
        }

        let segments = segmentRanges(of: transcript)
        // 区間をつなげる長さの上限（これより長い区間は、どの起動フレーズとも一致しない）
        let maxLength = (table.keys.map(\.count).max() ?? 0)
            + (leadingFillers.map(\.count).max() ?? 0)
            + (trailingSuffixes.map(\.count).max() ?? 0)
        var parts: [SnippetMatch.Part] = []
        var pendingStart = transcript.startIndex
        var i = 0
        while i < segments.count {
            // i から始まる区間の並びのうち、一致する最も長いもの
            var found: (end: Int, snippet: Snippet)?
            for j in i..<segments.count {
                let run = transcript[segments[i].lowerBound..<segments[j].upperBound]
                if normalize(String(run)).count > maxLength { break }
                if let snippet = lookup(run) { found = (j, snippet) }
            }
            guard let found else {
                i += 1
                continue
            }
            appendText(transcript[pendingStart..<segments[i].lowerBound], to: &parts)
            parts.append(.snippet(found.snippet))
            pendingStart = segments[found.end].upperBound
            i = found.end + 1
        }
        guard parts.contains(where: { if case .snippet = $0 { true } else { false } }) else { return nil }
        appendText(transcript[pendingStart...], to: &parts)
        return SnippetMatch(parts: parts)
    }

    /// 区切り（空白・句読点）で分けた区間の範囲
    static func segmentRanges(of text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let isSeparator = text[index].unicodeScalars.allSatisfy { removedCharacters.contains($0) }
            if isSeparator {
                if let s = start { ranges.append(s..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
            index = text.index(after: index)
        }
        if let s = start { ranges.append(s..<text.endIndex) }
        return ranges
    }

    /// スニペットの前後に残った文を足す。スニペットと接する読点・空白は落とし、中身のない文（記号やフィラーだけ）は捨てる
    private static func appendText(_ text: Substring, to parts: inout [SnippetMatch.Part]) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 前の文の末尾の読点（「よろしくお願いします、」の「、」）は落とす。句点・疑問符などは残す
        while let last = trimmed.last, "、,，".contains(last) { trimmed.removeLast() }  // skip-tr（照らし合わせ・区切りに使う記号）
        // 後ろの文の先頭の区切り（「、以上です」の「、」）は落とす
        while let first = trimmed.unicodeScalars.first, removedCharacters.contains(first) { trimmed.removeFirst() }
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalize(trimmed)
        guard !normalized.isEmpty, !leadingFillers.contains(normalized) else { return }
        parts.append(.text(trimmed))
    }
}

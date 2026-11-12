import Foundation

/// ユーザー辞書。設定の dictionaryText（1 行 1 項目）を読み、語と置き換えルールに分ける。
///
/// 書き方:
///
///     Stockmark                              … 語だけ。認識のヒントと Gemini に渡す（今までの書き方）
///     ストックマーク => Stockmark               … 置き換えルール。左の読み・誤認識を右の表記にする
///     えーにゅーす, エーニュース => Anews        … 左は「,」「、」で区切って複数書ける
///     # メモ                                  … 「#」で始まる行は無視する
///
/// 矢印は `=>` のほか、全角の `＝＞` と `→` も使える（日本語入力のままでも書けるように）。
///
/// 置き換えの規則（`apply(to:)`）:
/// - 英字の大文字小文字、全角と半角（ＡＢＣ／ABC、ｽﾄｯｸ／ストック）、空白の有無は区別せずに探す。
///   置き換えた後は、右に書いた表記そのものになる。
/// - ひらがなとカタカナは区別する（「すとっくまーく」は「ストックマーク」のルールでは置き換えない）。
///   どちらでも認識されるなら、左に両方書く。
/// - 部分一致による誤爆を防ぐため、次の場合は置き換えない。
///   - 左が英数字で始まる（終わる）とき、直前（直後）も英数字（例: `ai => AI` は OpenAI の中では効かない）
///   - 左がカタカナで始まる（終わる）とき、直前（直後）もカタカナか「ー」（例: `マーク => Mark` は
///     マークダウンやストックマークの中では効かない）
///   - 左が 1 文字だけのルール（漢字 1 字などは、ほかの語の一部に当たりやすい）
/// - 同じ位置に当てはまるルールが複数あれば、左が長いものを使う。長さも同じなら上の行を使う。
/// - 左から右へ 1 回だけ置き換える。置き換えた後の文字に、ほかのルールを重ねて当てない。
struct UserDictionary: Equatable {
    /// 辞書の 1 行。語も置き換えルールも `Entry` で表し、コメントと空行はそのまま残す。
    enum Line: Equatable {
        case entry(Entry)
        /// 空行・コメント（書かれたまま保つ）
        case other(String)
    }

    struct Entry: Equatable {
        /// 矢印の左（読み・誤認識）。書かれたままの文字列。語だけの行では空
        var reading: String
        /// 矢印の右（正しい表記）。語だけの行ではその語
        var spelling: String

        /// 左を区切った読みの一覧
        var sources: [String] {
            reading.split(whereSeparator: { UserDictionary.sourceSeparators.contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        var isRule: Bool { !sources.isEmpty }

        /// 辞書の 1 行として書き出す
        var line: String {
            let reading = reading.trimmingCharacters(in: .whitespaces)
            let spelling = spelling.trimmingCharacters(in: .whitespaces)
            return reading.isEmpty ? spelling : "\(reading) => \(spelling)"
        }
    }

    /// 実際に置き換えに使うルール
    struct Rule: Equatable, Hashable {
        var sources: [String]
        var target: String
    }

    static let arrows = ["=>", "＝＞", "→"]
    static let sourceSeparators: Set<Character> = [",", "、", "，"]  // skip-tr（照らし合わせ・区切りに使う記号）
    /// これより短い読みは誤爆しやすいので使わない
    static let minimumSourceLength = 2

    var lines: [Line]

    init(text: String) {
        lines = text.components(separatedBy: .newlines).map(Self.parseLine)
    }

    init(lines: [Line]) {
        self.lines = lines
    }

    // 設計判断: DEC-DIC-080
    static func parseLine(_ raw: String) -> Line {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { return .other(raw) }
        // いちばん左にある矢印で分ける
        let hit = arrows.compactMap { arrow in line.range(of: arrow) }.min { $0.lowerBound < $1.lowerBound }
        guard let hit else { return .entry(Entry(reading: "", spelling: line)) }
        return .entry(Entry(
            reading: String(line[..<hit.lowerBound]).trimmingCharacters(in: .whitespaces),
            spelling: String(line[hit.upperBound...]).trimmingCharacters(in: .whitespaces)))
    }

    var text: String {
        lines.map {
            switch $0 {
            case .entry(let entry): entry.line
            case .other(let raw): raw
            }
        }.joined(separator: "\n")
    }

    var entries: [Entry] {
        lines.compactMap { if case .entry(let e) = $0 { e } else { nil } }
    }

    // MARK: - 使う側に渡すもの

    /// 置き換えに使うルール（問題のある読みは除く）
    var rules: [Rule] {
        var seen = Set<[Character]>()
        var rules: [Rule] = []
        for entry in entries where entry.isRule {
            let target = entry.spelling.trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { continue }
            let sources = entry.sources.filter { source in
                let key = Self.matchKey(source)
                guard key.count >= Self.minimumSourceLength, !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
            if !sources.isEmpty { rules.append(Rule(sources: sources, target: target)) }
        }
        return rules
    }

    /// 正しい表記の一覧（語だけの行と、ルールの右側）。Gemini の「ユーザー辞書」に渡す
    var spellings: [String] {
        Self.unique(entries.map { $0.spelling.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    // 設計判断: DEC-DIC-009
    /// 音声認識の語彙ヒント（AnalysisContext.contextualStrings）に渡す語。
    /// 正しい表記に加えて、ルールの読みも渡す（読みどおりに認識されれば、後の置き換えで確実に直せる）
    var contextualStrings: [String] {
        Self.unique(spellings + rules.flatMap(\.sources))
    }

    /// 行ごとの注意（表の UI に出す）。キーは `lines` の添字
    var issues: [Int: String] {
        var result: [Int: String] = [:]
        var seen = Set<[Character]>()
        for (index, line) in lines.enumerated() {
            guard case .entry(let entry) = line, entry.isRule else { continue }
            if entry.spelling.trimmingCharacters(in: .whitespaces).isEmpty {
                result[index] = tr("正しい表記が空なので、置き換えません")
                continue
            }
            var notes: [String] = []
            for source in entry.sources {
                let key = Self.matchKey(source)
                if key.count < Self.minimumSourceLength {
                    notes.append(tr("「%@」は 1 文字なので使いません（ほかの語の一部に当たりやすいため）", "\(source)"))
                } else if seen.contains(key) {
                    notes.append(tr("「%@」は上の行にもあるので、上の行を使います", "\(source)"))
                } else {
                    seen.insert(key)
                }
            }
            if !notes.isEmpty { result[index] = notes.joined(separator: "\n") }
        }
        return result
    }

    // MARK: - 置き換え

    struct Replacement: Equatable {
        /// 文中で当てはまった部分（書かれていたまま）
        var matched: String
        var target: String
    }

    // 要件: REQ-DIC-070
    func apply(to text: String) -> String {
        applyWithLog(to: text).text
    }

    // 設計判断: DEC-DIC-081, DEC-DIC-083
    /// 置き換えた結果と、どこをどう置き換えたか
    func applyWithLog(to text: String) -> (text: String, replacements: [Replacement]) {
        let rules = rules
        guard !rules.isEmpty, !text.isEmpty else { return (text, []) }

        // 照合用の型: 読み（空白を除いて畳んだ文字列）→ 表記。先頭の文字ごとに、長い順に並べる
        struct Pattern { var key: [Character]; var target: String; var first: CharClass; var last: CharClass }
        var patterns: [Character: [Pattern]] = [:]
        for rule in rules {
            for source in rule.sources {
                let key = Self.matchKey(source)
                guard let first = key.first, let last = key.last else { continue }
                patterns[first, default: []].append(
                    Pattern(key: key, target: rule.target, first: Self.charClass(first), last: Self.charClass(last)))
            }
        }
        for (k, list) in patterns {
            // 長い順。長さが同じなら書いた順（sort は安定ではないので、添字で並べる）
            patterns[k] = list.enumerated()
                .sorted { $0.element.key.count != $1.element.key.count ? $0.element.key.count > $1.element.key.count : $0.offset < $1.offset }
                .map(\.element)
        }

        let chars = Array(text)
        // 空白を除いて畳んだ文字の並びと、それぞれが元の何文字目から来たか
        var units: [Character] = []
        var unitOrigin: [Int] = []
        var firstUnit = [Int](repeating: -1, count: chars.count)
        // 前後の文字の種類（境界の判定用）。元の文字を畳んだものの先頭・末尾で見る
        var headClass: [CharClass] = []
        var tailClass: [CharClass] = []
        for (i, c) in chars.enumerated() {
            let folded = Self.fold(c)
            headClass.append(folded.first.map(Self.charClass) ?? .other)
            tailClass.append(folded.last.map(Self.charClass) ?? .other)
            guard !c.isWhitespace, !folded.isEmpty else { continue }
            firstUnit[i] = units.count
            for f in folded {
                units.append(f)
                unitOrigin.append(i)
            }
        }

        var output = ""
        var replacements: [Replacement] = []
        var i = 0
        while i < chars.count {
            let u = firstUnit[i]
            if u >= 0, let candidates = patterns[units[u]] {
                var matchedEnd: Int?
                var matchedTarget = ""
                for pattern in candidates {
                    let end = u + pattern.key.count
                    guard end <= units.count, Array(units[u..<end]) == pattern.key else { continue }
                    let lastChar = unitOrigin[end - 1]
                    // 元の 1 文字が畳んで複数になった途中で切れていないか
                    if end < units.count, unitOrigin[end] == lastChar { continue }
                    // 語の境界
                    if i > 0, Self.joins(tailClass[i - 1], pattern.first) { continue }
                    if lastChar + 1 < chars.count, Self.joins(pattern.last, headClass[lastChar + 1]) { continue }
                    matchedEnd = lastChar + 1
                    matchedTarget = pattern.target
                    break
                }
                if let end = matchedEnd {
                    output += matchedTarget
                    replacements.append(Replacement(matched: String(chars[i..<end]), target: matchedTarget))
                    i = end
                    continue
                }
            }
            output.append(chars[i])
            i += 1
        }
        return (output, replacements)
    }

    // MARK: - 文字の扱い

    enum CharClass { case latin, katakana, other }

    // 設計判断: DEC-DIC-081
    /// 大文字小文字・全角半角を区別しないように畳む
    static func fold(_ c: Character) -> [Character] {
        Array(String(c).folding(options: [.caseInsensitive, .widthInsensitive], locale: nil))
    }

    /// 照合に使う形（畳んで、空白を除く）
    static func matchKey(_ s: String) -> [Character] {
        s.filter { !$0.isWhitespace }.flatMap(fold)
    }

    // 設計判断: DEC-DIC-082
    /// 語の種類。latin は、空白で語を区切る文字（アクセント付きを含むラテン文字・ギリシャ文字・キリル文字・アラビア文字・
    /// デーヴァナーガリーなど）の英数字。漢字・ひらがな・ハングルは語の区切りがなく助詞が続くので other
    static func charClass(_ c: Character) -> CharClass {
        guard let scalar = c.unicodeScalars.first else { return .other }
        switch scalar.value {
        case 0x30A1...0x30FA, 0x30FC...0x30FE, 0x31F0...0x31FF: return .katakana  // 「・」(30FB) は区切りとして扱う
        case 0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7FF: return .other  // ハングル
        default:
            if TextSpacing.writesWithoutSpaces(scalar) { return .other }
            return c.isLetter || c.isNumber ? .latin : .other
        }
    }

    // 設計判断: DEC-DIC-082
    /// 2 つの文字が同じ語の一部としてつながるか（空白で語を区切る文字の英数字どうし、カタカナどうし）
    static func joins(_ a: CharClass, _ b: CharClass) -> Bool {
        a == b && a != .other
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}

extension AppSettings {
    /// ユーザー辞書（語と置き換えルール）
    var userDictionary: UserDictionary { UserDictionary(text: dictionaryText) }
}

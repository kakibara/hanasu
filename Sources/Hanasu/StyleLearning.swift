import Compression
import Foundation

// 文章から文体を学ぶ（REQ-DIC-022）。ファイルの読み込み（StyleSourceReader・DocxText）と、AI に文体のルールを書き出させる処理（StyleLearner）。
// Windows 版は windows/Hanasu.Core/Dictation/StyleLearning.cs（同じ規則。共有の固定のファイル common/testdata/style/ で確かめる）。

// MARK: - ファイルの読み込み

/// 読めなかった理由
enum StyleSourceError: Error, Equatable {
    /// 扱わない拡張子
    case unsupported
    /// 壊れている・文字コードが分からない
    case unreadable
    /// 大きすぎる（ファイルが 20 MB より大きい・展開すると 50 MB を超える）
    case tooLarge

    /// cases.json の error と同じ名前
    var code: String {
        switch self {
        case .unsupported: "unsupported"
        case .unreadable: "unreadable"
        case .tooLarge: "tooLarge"
        }
    }

    var message: String {
        switch self {
        case .unsupported: tr("読めない形式です（.docx・.txt・.md を選んでください）。")
        case .unreadable: tr("ファイルが壊れているか、読めない文字コードです。")
        case .tooLarge: tr("ファイルが大きすぎます（20 MB まで）。")
        }
    }
}

// 要件: REQ-DIC-022
// 設計判断: DEC-DIC-211
/// 文体を学ぶ材料のファイルを、本文の文字列にする。改行は LF にそろえ、前後の空白は取らない
enum StyleSourceReader {
    static let extensions = ["docx", "txt", "md", "markdown"]
    static let maxFileBytes = 20 * 1024 * 1024

    static func read(_ url: URL) -> Result<String, StyleSourceError> {
        let ext = url.pathExtension.lowercased()
        guard extensions.contains(ext) else { return .failure(.unsupported) }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxFileBytes else { return .failure(.tooLarge) }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
        if ext == "docx" { return DocxText.read(data) }
        return decodeText(data).map(normalizeNewlines) ?? .failure(.unreadable)
    }

    // 設計判断: DEC-DIC-211
    /// BOM で UTF-8・UTF-16（LE・BE）を見分け、BOM がなければ UTF-8、UTF-8 として正しくなければ Shift_JIS（CP932）で読む
    static func decodeText(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
        if bytes.starts(with: [0xFF, 0xFE]) { return String(data: data.dropFirst(2), encoding: .utf16LittleEndian) }
        if bytes.starts(with: [0xFE, 0xFF]) { return String(data: data.dropFirst(2), encoding: .utf16BigEndian) }
        if let text = String(data: data, encoding: .utf8) { return text }
        let cp932 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        return String(data: data, encoding: cp932)
    }

    static func normalizeNewlines(_ text: String) -> Result<String, StyleSourceError> {
        .success(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
    }
}

// 要件: REQ-DIC-022
// 設計判断: DEC-DIC-211
/// .docx の本文（word/document.xml）を読む。zip は中央ディレクトリから引き、raw deflate は Apple の Compression で展開する。
/// 段落（w:p）を改行、w:t を文字、w:tab をタブ、w:br・w:cr を改行にする。表のセルも段落として読む。
/// 番号・画像・脚注・コメント・ヘッダーとフッター・消した部分（w:del）・書式（w:pPr・w:rPr。タブ位置の定義を含む）・フィールドのコード（w:instrText）は読まない
enum DocxText {
    static let maxDocumentBytes = 50 * 1024 * 1024
    static let documentPath = "word/document.xml"

    static func read(_ data: Data) -> Result<String, StyleSourceError> {
        switch ZipEntryReader.extract(documentPath, from: data, maxSize: maxDocumentBytes) {
        case .failure(let error): return .failure(error)
        case .success(let xml): return parse(xml)
        }
    }

    static func parse(_ xml: Data) -> Result<String, StyleSourceError> {
        // DTD は読まない（実体の展開で大きくなるのを防ぐ。Windows の DtdProcessing.Prohibit と同じく、あれば読めないものにする）
        if xml.range(of: Data("<!DOCTYPE".utf8)) != nil { return .failure(.unreadable) }
        let parser = XMLParser(data: xml)
        let delegate = Collector()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { return .failure(.unreadable) }
        return .success(delegate.paragraphs.joined(separator: "\n"))
    }

    private final class Collector: NSObject, XMLParserDelegate {
        static let namespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        /// 中を読まない要素（段落と文字の書式。タブ位置の定義 w:tabs/w:tab を含む。消した部分 w:del）
        static let skipped: Set<String> = ["pPr", "rPr", "del"]
        var paragraphs: [String] = []
        private var open: [String] = []
        private var inText = false
        private var skipDepth = 0

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            guard namespaceURI == Self.namespace else { return }
            if skipDepth > 0 || Self.skipped.contains(name) {
                skipDepth += 1
                return
            }
            switch name {
            case "p": open.append("")
            case "t": inText = true
            case "tab": append("\t")
            case "br", "cr": append("\n")
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard namespaceURI == Self.namespace else { return }
            if skipDepth > 0 {
                skipDepth -= 1
                return
            }
            switch name {
            case "p": if let last = open.popLast() { paragraphs.append(last) }
            case "t": inText = false
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { append(string) }
        }

        private func append(_ text: String) {
            guard !open.isEmpty else { return }
            open[open.count - 1] += text
        }
    }
}

/// zip から 1 つのファイルを取り出す（.docx 用の小さな読み手。保存（0）と deflate（8）だけ。ZIP64 は読まない）
enum ZipEntryReader {
    static func extract(_ path: String, from data: Data, maxSize: Int) -> Result<Data, StyleSourceError> {
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }

        // 終わりの中央ディレクトリの記録（後ろから探す。コメントは 65,535 バイトまで）
        guard bytes.count >= 22 else { return .failure(.unreadable) }
        var eocd: Int?
        var i = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65_535)
        while i >= lowest {
            if u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard let eocd else { return .failure(.unreadable) }
        let entries = u16(eocd + 10)
        var offset = u32(eocd + 16)
        for _ in 0..<entries {
            guard offset + 46 <= bytes.count, u32(offset) == 0x0201_4B50 else { return .failure(.unreadable) }
            let method = u16(offset + 10)
            let compressedSize = u32(offset + 20)
            let size = u32(offset + 24)
            let nameLength = u16(offset + 28)
            let extraLength = u16(offset + 30)
            let commentLength = u16(offset + 32)
            let localOffset = u32(offset + 42)
            guard offset + 46 + nameLength <= bytes.count else { return .failure(.unreadable) }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            offset += 46 + nameLength + extraLength + commentLength
            guard name == path else { continue }

            guard size <= maxSize else { return .failure(.tooLarge) }
            guard localOffset + 30 <= bytes.count, u32(localOffset) == 0x0403_4B50 else { return .failure(.unreadable) }
            let start = localOffset + 30 + u16(localOffset + 26) + u16(localOffset + 28)
            guard start + compressedSize <= bytes.count else { return .failure(.unreadable) }
            let compressed = bytes[start..<(start + compressedSize)]
            switch method {
            case 0:
                return compressedSize == size ? .success(Data(compressed)) : .failure(.unreadable)
            case 8:
                guard size > 0 else { return .success(Data()) }
                var output = [UInt8](repeating: 0, count: size)
                let written = compressed.withContiguousStorageIfAvailable { source in
                    compression_decode_buffer(&output, size, source.baseAddress!, compressedSize, nil, COMPRESSION_ZLIB)
                } ?? 0
                return written == size ? .success(Data(output)) : .failure(.unreadable)
            default:
                return .failure(.unreadable)
            }
        }
        return .failure(.unreadable)
    }
}

// MARK: - 学ぶ

/// AI が書き出した文体
struct LearnedStyle: Equatable {
    var name: String
    var language: PromptLanguage
    var rules: [String]
}

enum StyleLearningError: LocalizedError, Equatable {
    case tooShort
    case invalidResponse
    case unknownLanguage(String)

    var errorDescription: String? {
        switch self {
        case .tooShort: tr("文章が短すぎます。%@ 字以上入れてください。", String(StyleLearner.minimumCharacters))
        case .invalidResponse: tr("AI の答えから文体のルールを読み取れませんでした。もう一度試してください。")
        case .unknownLanguage(let code): tr("文章の言語（%@）は対応していません。", code)
        }
    }
}

// 要件: REQ-DIC-022
// 設計判断: DEC-DIC-210, DEC-DIC-212
/// 文章を「議事録」の AI に送り、文体のルール（12 個まで）・名前の案・文章の言語を書き出してもらう。文章は保存しない
enum StyleLearner {
    // 設計判断: DEC-DIC-212
    static let minimumCharacters = 100
    /// Gemini・Claude に送る上限（字）
    static let characterLimit = 30_000
    /// 入力欄に入れる上限（字）
    static let inputLimit = 100_000
    // 設計判断: DEC-DIC-210
    static let maxRules = 12
    static let timeout: TimeInterval = 120

    // 設計判断: DEC-DIC-212
    /// 字数（Unicode のスカラー値。Windows の EnumerateRunes().Count() と同じ）
    static func count(_ text: String) -> Int { text.unicodeScalars.count }

    /// 先頭から n 字（スカラー値）まで
    static func prefix(_ text: String, characters n: Int) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.prefix(n))
        return String(scalars)
    }

    /// 対応する言語のコード（AI に返させる値）
    static var languageCodes: String { PromptLanguage.allCases.map(\.rawValue).joined(separator: ", ") }

    // 要件: REQ-COM-061
    static var instruction: String { Prompts.text("styleLearn.system", ["languages": languageCodes]) }

    static func userPrompt(material: String) -> String {
        Prompts.text("styleLearn.user", ["material": material])
    }

    // 設計判断: DEC-DIC-212
    /// 送る上限。Gemini・Claude は字数、ローカル・Apple は文脈の長さから出力・指示・枠・余白を引いたトークン数（DictionarySuggester.budget と同じ出し方）
    static func budget(for client: TextAIClient) -> DictionarySuggester.Budget {
        let frame = AppleFMClient.estimateTokens(instruction + userPrompt(material: "")) + LongInputFitter.margin
        switch client.backend {
        case .gemini, .claude:
            return .characters(characterLimit)
        case .local(let local):
            return .tokens(max(0, local.model.contextLength - local.maxOutputTokens(.short) - frame))
        case .appleFM:
            return .tokens(max(0, AppleFMClient.contextLength - AppleFMClient.maxOutputTokens(.short) - frame))
        }
    }

    /// 送る材料（前後の空白を除き、上限までを先頭から）
    struct Material: Equatable {
        var text: String
        /// 入力した字数（前後の空白を除く）
        var totalCharacters: Int
        var usedCharacters: Int { StyleLearner.count(text) }
        var truncated: Bool { usedCharacters < totalCharacters }
    }

    // 設計判断: DEC-DIC-212
    static func material(_ text: String, budget: DictionarySuggester.Budget) -> Material {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let total = count(trimmed)
        switch budget {
        case .characters(let limit):
            return Material(text: total <= limit ? trimmed : prefix(trimmed, characters: limit), totalCharacters: total)
        case .tokens(let limit):
            if AppleFMClient.estimateTokens(trimmed) <= limit { return Material(text: trimmed, totalCharacters: total) }
            // 入る長さを二分探索で探す（見積もりは長さに対して増えていく）
            var low = 0
            var high = total
            while low < high {
                let middle = (low + high + 1) / 2
                if AppleFMClient.estimateTokens(prefix(trimmed, characters: middle)) <= limit { low = middle } else { high = middle - 1 }
            }
            return Material(text: prefix(trimmed, characters: low), totalCharacters: total)
        }
    }

    // 設計判断: DEC-DIC-210
    /// AI の答え（JSON）を読む。コードブロックで囲まれていても読めるよう、最初の { から最後の } までを使う
    static func parse(_ text: String) throws -> LearnedStyle {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            throw StyleLearningError.invalidResponse
        }
        struct Envelope: Decodable {
            var name: String?
            var language: String?
            var rules: [String]?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(text[start...end].utf8)) else {
            throw StyleLearningError.invalidResponse
        }
        let rules = (envelope.rules ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(maxRules)
        guard !rules.isEmpty else { throw StyleLearningError.invalidResponse }
        let code = (envelope.language ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let language = PromptLanguage.allCases.first(where: { $0.rawValue.lowercased() == code.lowercased() }) else {
            throw StyleLearningError.unknownLanguage(code)
        }
        return LearnedStyle(name: (envelope.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                            language: language, rules: Array(rules))
    }

    // 要件: REQ-DIC-022
    // 設計判断: DEC-DIC-210
    /// 学ぶ。材料の区切りのタグは無害にしてから <material> に入れる
    static func learn(text: String, client: TextAIClient, model: String) async throws -> LearnedStyle {
        var client = client
        client.timeout = timeout
        let material = material(text, budget: budget(for: client))
        guard material.totalCharacters >= minimumCharacters else { throw StyleLearningError.tooShort }
        let answer = try await client.generate(
            systemInstruction: instruction,
            userText: userPrompt(material: PromptText.neutralizeDelimiters(material.text)),
            model: model)
        return try parse(answer)
    }
}

import Foundation

// 設計判断: DEC-COM-174
/// 文のかけら（認識の区切り・続く発言・スニペット）をつなぐときに、あいだに空白を入れるかの決まり。
/// 日本語・中国語は語のあいだに空白を書かないので入れず、英語・韓国語など空白で語を区切る言語では 1 つ入れる。
/// Windows 版の `TextSpacing` と同じ決まり（両方を直す）
enum TextSpacing {
    /// a と b をつなぐ。境目に空白がなく、どちらの側も空白を書かない文字（漢字・かな・全角の記号）でなければ空白を 1 つ入れる
    static func join(_ a: String, _ b: String) -> String {
        needsSpace(a, b) ? a + " " + b : a + b
    }

    /// 並びをつなぐ（空のかけらは飛ばす）
    static func join(_ pieces: [String]) -> String {
        pieces.reduce("") { $1.isEmpty ? $0 : join($0, $1) }
    }

    /// 音声入力の認識の区切りをつなぐ。文字起こしの言語が日本語・中国語なら、境目の文字によらず空白を入れない
    /// （「090」と「1234」のように、数字や英字の途中で区切りが確定しても前と同じにする）
    static func join(_ a: String, _ b: String, localeIdentifier: String) -> String {
        usesSpaces(localeIdentifier: localeIdentifier) ? join(a, b) : a + b
    }

    static func join(_ pieces: [String], localeIdentifier: String) -> String {
        usesSpaces(localeIdentifier: localeIdentifier) ? join(pieces) : pieces.joined()
    }

    /// 文字起こしの言語が、語のあいだに空白を書く言語か（日本語・中国語は書かない。空は日本語として扱う）
    static func usesSpaces(localeIdentifier: String) -> Bool {
        let code = localeIdentifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { $0.lowercased() } ?? "ja"
        return !["ja", "zh", "yue"].contains(code)
    }

    static func needsSpace(_ a: String, _ b: String) -> Bool {
        guard let last = a.unicodeScalars.last, let first = b.unicodeScalars.first else { return false }
        if CharacterSet.whitespacesAndNewlines.contains(last) || CharacterSet.whitespacesAndNewlines.contains(first) { return false }
        if writesWithoutSpaces(last) || writesWithoutSpaces(first) { return false }
        // 閉じる記号・句読点の前、開く記号の後には入れない
        if ".,!?;:%)]}…'’”»،؛؟۔।॥".unicodeScalars.contains(first) { return false }  // skip-tr（照らし合わせに使う記号）
        if "([{‘“«¿¡".unicodeScalars.contains(last) { return false }  // skip-tr（照らし合わせに使う記号）
        return true
    }

    /// 語のあいだに空白を書かない文字（漢字・ひらがな・カタカナ・注音・CJK の記号・全角の形）。ハングルは空白で区切るので含めない
    static func writesWithoutSpaces(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x2E80...0x2FFF,  // 部首
             0x3000...0x30FF,  // CJK の記号・句読点、ひらがな、カタカナ
             0x3100...0x312F, 0x31A0...0x31FF,  // 注音、カタカナの拡張
             0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,  // 漢字
             0xFE30...0xFE4F,  // CJK の互換の形
             0xFF00...0xFFEF,  // 全角・半角の形
             0x20000...0x3FFFF:  // 漢字の拡張
            true
        default:
            false
        }
    }
}

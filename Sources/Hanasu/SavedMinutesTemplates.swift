import Foundation

// 要件: REQ-MTG-034
// 設計判断: DEC-MTG-071
/// 名前を付けて保存した議事録のテンプレート（見出しの構成や書き方の指示）。
struct SavedMinutesTemplate: Codable, Identifiable, Hashable {
    var id = UUID()
    /// 選ぶときに出す名前（一覧の中で重複しない）
    var name: String
    /// 見出しの構成や書き方の指示。カスタムの型の指示（`<user_template>`）としてそのまま渡す
    var instructions: String
}

/// 保存したテンプレートの一覧（UserDefaults の JSON）と、その選び方・検査。
/// 画面は `@AppStorage(SavedMinutesTemplateStore.listKey)` で JSON の文字列を持ち、`decode` / `encode` で出し入れする。
enum SavedMinutesTemplateStore {
    static let listKey = "meetingSavedMinutesTemplates"
    /// 記録前の型の選択（`MinutesTemplateStore.templateKey`）に保存テンプレートを選んだときの値の先頭
    static let selectionPrefix = "saved:"

    static func decode(_ json: String) -> [SavedMinutesTemplate] {
        guard let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([SavedMinutesTemplate].self, from: data) else { return [] }
        return list
    }

    static func encode(_ list: [SavedMinutesTemplate]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(list) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func load(_ defaults: UserDefaults = .standard) -> [SavedMinutesTemplate] {
        decode(defaults.string(forKey: listKey) ?? "")
    }

    static func save(_ list: [SavedMinutesTemplate], to defaults: UserDefaults = .standard) {
        defaults.set(encode(list), forKey: listKey)
    }

    /// 型の選択欄に保存する値（`saved:<id>`）
    static func selection(for template: SavedMinutesTemplate) -> String {
        selectionPrefix + template.id.uuidString
    }

    /// 型の選択の値から、保存したテンプレートを探す。消した・見つからないときは nil
    static func template(forSelection value: String, in list: [SavedMinutesTemplate]) -> SavedMinutesTemplate? {
        guard value.hasPrefix(selectionPrefix),
              let id = UUID(uuidString: String(value.dropFirst(selectionPrefix.count))) else { return nil }
        return list.first { $0.id == id }
    }

    static func trimmedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 同じ名前（前後の空白と大文字小文字の違いは無視）がほかにあるか。`excluding` は編集中のテンプレート自身
    static func isNameTaken(_ name: String, in list: [SavedMinutesTemplate], excluding id: UUID? = nil) -> Bool {
        let wanted = trimmedName(name).lowercased()
        return list.contains { $0.id != id && trimmedName($0.name).lowercased() == wanted }
    }

    enum Problem: Equatable {
        case emptyName
        case duplicateName
        case emptyInstructions

        var message: String {
            switch self {
            case .emptyName: "名前を入力してください"
            case .duplicateName: "同じ名前のテンプレートがあります"
            case .emptyInstructions: "指示を入力してください"
            }
        }
    }

    /// 保存できない理由（なければ nil）
    static func problem(name: String, instructions: String, in list: [SavedMinutesTemplate], excluding id: UUID? = nil) -> Problem? {
        if trimmedName(name).isEmpty { return .emptyName }
        if isNameTaken(name, in: list, excluding: id) { return .duplicateName }
        if instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyInstructions }
        return nil
    }

    /// 「名前 2」「名前 3」…と、重複しない名前を作る（複製・新規用）
    static func uniqueName(from base: String, in list: [SavedMinutesTemplate]) -> String {
        var stem = trimmedName(base).isEmpty ? "新しいテンプレート" : trimmedName(base)
        if !isNameTaken(stem, in: list) { return stem }
        // 「営業定例 2」を複製して「営業定例 2 2」にならないよう、末尾の番号は外す
        if let space = stem.lastIndex(of: " "), Int(stem[stem.index(after: space)...]) != nil {
            stem = String(stem[..<space])
        }
        var n = 2
        while isNameTaken("\(stem) \(n)", in: list) { n += 1 }
        return "\(stem) \(n)"
    }

    /// 追加する。問題があれば追加せず理由を返す
    @discardableResult
    static func add(name: String, instructions: String, to list: inout [SavedMinutesTemplate]) -> Problem? {
        if let problem = problem(name: name, instructions: instructions, in: list) { return problem }
        list.append(SavedMinutesTemplate(name: trimmedName(name), instructions: instructions))
        return nil
    }

    /// 名前・指示を直す。問題があれば直さず理由を返す
    @discardableResult
    static func update(id: UUID, name: String, instructions: String, in list: inout [SavedMinutesTemplate]) -> Problem? {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return nil }
        if let problem = problem(name: name, instructions: instructions, in: list, excluding: id) { return problem }
        list[index].name = trimmedName(name)
        list[index].instructions = instructions
        return nil
    }

    /// 複製（名前は重複しないよう「〇〇 2」にする）。複製したテンプレートの ID を返す
    @discardableResult
    static func duplicate(id: UUID, in list: inout [SavedMinutesTemplate]) -> UUID? {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return nil }
        let source = list[index]
        let copy = SavedMinutesTemplate(name: uniqueName(from: source.name, in: list), instructions: source.instructions)
        list.insert(copy, at: index + 1)
        return copy.id
    }

    static func remove(id: UUID, from list: inout [SavedMinutesTemplate]) {
        list.removeAll { $0.id == id }
    }
}

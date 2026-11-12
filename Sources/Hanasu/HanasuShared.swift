import Foundation

// 要件: REQ-COM-189, REQ-COM-193, REQ-DIC-160
// 設計判断: DEC-COM-187, DEC-COM-191
/// hanasu コマンドの、Mac と Windows で共有する文と一覧（Resources/Command/hanasu.json）。
/// MCP のツールの説明・エージェントへの説明（英語。外への約束）と、組み込みの既定の文体の一覧（DEC-DIC-190）。
/// Windows 版は同じファイルを Hanasu.Core に埋め込んで読む
enum HanasuShared {
    /// ${device} に入れる、このマシンの呼び方
    static let device = "this Mac"

    static let data: [String: Any] = {
        guard let url = HanasuResources.url(forResource: "hanasu", withExtension: "json", subdirectory: "Command"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }()

    /// 入れ子のキーの文字列。${device} と args を埋める。なければ空
    static func text(_ path: String, _ args: [String: String] = [:]) -> String {
        var node: Any? = data
        for key in path.split(separator: ".") { node = (node as? [String: Any])?[String(key)] }
        guard let template = node as? String else { return "" }
        return Prompts.fill(template, args.merging(["device": device]) { a, _ in a })
    }

    /// 入れ子のキーの文字列の配列（1 行 1 要素）。${device} と args を埋める
    static func lines(_ path: String, _ args: [String: String] = [:]) -> [String] {
        var node: Any? = data
        for key in path.split(separator: ".") { node = (node as? [String: Any])?[String(key)] }
        return ((node as? [String]) ?? []).map { Prompts.fill($0, args.merging(["device": device]) { a, _ in a }) }
    }

    // 要件: REQ-DIC-020, REQ-DIC-160
    // 設計判断: DEC-DIC-190
    /// 組み込みの既定の文体のうち、Mac のアプリ（bundle ID）があるもの（並びはファイルのまま）
    static var defaultAppStyles: [AppStyle] {
        ((data["defaultAppStyles"] as? [[String: Any]]) ?? []).compactMap { entry in
            guard let bundleID = entry["mac"] as? String, let name = entry["name"] as? String,
                  let preset = (entry["preset"] as? String).flatMap(AppStylePreset.init(rawValue:)) else { return nil }
            return AppStyle(bundleID: bundleID, name: name, preset: preset)
        }
    }
}

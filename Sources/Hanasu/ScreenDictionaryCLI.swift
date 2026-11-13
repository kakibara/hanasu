import AppKit
import SwiftUI

// 画面から辞書の候補を探す（ScreenDictionaryWindow.swift・DictionarySuggester.screenMaterial）の確認用の CLI モード:
//   Hanasu --test-screen-dictionary
//     材料（語が先・上限で外したら truncated）・画面からの候補の絞り込み（表記はいつも材料と照らし合わせ、読みは推測を許す・
//     読みの数と長さ）・既定の引数の絞り込みが今と同じこと・共有の例（common/testdata/logic/screen-terms.json の terms）・
//     選んだ読みだけを足すことを確かめる。画面は撮らず、AI も呼ばない。失敗があれば終了コード 1
//   Hanasu --render-screen-dictionary <出力フォルダ>
//     候補の画面（許可がない・読んでいる・読んだ・一部だけ送る・候補・0 件・エラー・追加した）を PNG にする
// 実際に AI を呼ぶ確かめは `Hanasu --suggest-dictionary --screen | --screen-text <ファイル>`（DictionaryCLI.swift）
// 確かめ方: REQ-DIC-075
@MainActor
enum ScreenDictionaryCLI {
    static func runIfRequested(_ args: [String] = CommandLine.arguments) {
        if args.contains("--test-screen-dictionary") {
            exit(selfTest() ? 0 : 1)
        }
        if let index = args.firstIndex(of: "--render-screen-dictionary"), index + 1 < args.count {
            do {
                try render(to: URL(fileURLWithPath: args[index + 1], isDirectory: true))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
    }

    // MARK: - 自己テスト

    static func selfTest() -> Bool {
        var failures = 0
        func check(_ name: String, _ condition: Bool) {
            print("\(condition ? "OK" : "NG")  \(name)")
            if !condition { failures += 1 }
        }
        func line(_ text: String, y: Double) -> ScreenTextLine {
            ScreenTextLine(text: text, display: 0, inTarget: false, y: y, x: 0)
        }

        // 設計判断: DEC-DIC-231（材料）
        let lines = [line("J3 の進捗は Kubernetes で", y: 10), line("株式会社ストックマークの営業部", y: 30)]
        let material = DictionarySuggester.screenMaterial(lines, budget: .characters(DictionarySuggester.characterLimit))
        check("材料: 語の一覧と行の両方が入る", material.terms.contains("J3") && material.terms.contains("Kubernetes")
            && material.lines.contains("株式会社ストックマークの営業部"))
        check("材料: 上限に入れば truncated は立たない", !material.truncated)
        check("材料: 語が行より先に出る", (material.text.range(of: "J3")?.lowerBound ?? material.text.endIndex)
            < (material.text.range(of: "株式会社ストックマークの営業部")?.lowerBound ?? material.text.startIndex))
        check("材料: 見出しが入る", material.text.contains(Prompts.text("dictionarySuggest.screenTermsHeader"))
            && material.text.contains(Prompts.text("dictionarySuggest.screenLinesHeader")))
        let small = DictionarySuggester.screenMaterial(lines, budget: .characters(60))
        check("材料: 上限を超えたら外して truncated を立てる", small.truncated && small.text.count <= 60 + 10)
        check("材料: 外しても語を先に残す", !small.terms.isEmpty)
        check("材料: 文字がなければ空", DictionarySuggester.screenMaterial([], budget: .characters(1000)).isEmpty)

        // 設計判断: DEC-DIC-231（絞り込み）
        let text = material.text
        let existing = UserDictionary(text: "Hanasu\nスタックマーク => Stockmark")
        let found = DictionarySuggester.filterFromScreen([
            DictionaryCandidate(spelling: "J3", readings: ["Jスリー", "ジェイスリー"], reason: "型番"),
            DictionaryCandidate(spelling: "Stockmark AI", readings: ["ストックマークエーアイ"], reason: "AI が作った語"),
            DictionaryCandidate(spelling: "Kubernetes", readings: ["クバネティス", "クーベネティス", "クベルネテス", "キューベネティス", "クーバネティス"], reason: "製品名"),
            DictionaryCandidate(spelling: "営業部", readings: ["え", "営業部", "あいうえおかきくけこさしすせそたちつてとな"], reason: "読みがだめ"),
            DictionaryCandidate(spelling: "株式会社ストックマーク", readings: ["スタックマーク", "かぶしきがいしゃストックマーク"], reason: "社名"),
        ], existing: existing, material: text)
        let j3 = found.first { $0.spelling == "J3" }
        check("絞り込み: 材料に出てこない読み（推測）を残す", j3?.readings == ["Jスリー", "ジェイスリー"])
        check("絞り込み: 読みがあっても、材料に出てこない表記は除く", !found.contains { $0.spelling == "Stockmark AI" })
        check("絞り込み: 読みは 4 つまで", found.first { $0.spelling == "Kubernetes" }?.readings.count == DictionarySuggester.screenMaxReadings)
        check("絞り込み: 1 文字・表記と同じ・長すぎる読みは除く（表記は語だけで残る）",
              found.first { $0.spelling == "営業部" }?.readings.isEmpty == true)
        check("絞り込み: 既存のルールで使っている読みは除く", found.first { $0.spelling == "株式会社ストックマーク" }?.readings == ["かぶしきがいしゃストックマーク"])
        // 既定の引数では今までどおり（読みは材料に出てくること。表記は読みが残らないときだけ照らし合わせる）
        let legacy = DictionarySuggester.filter([
            DictionaryCandidate(spelling: "J3", readings: ["Jスリー"], reason: ""),
            DictionaryCandidate(spelling: "Stockmark", readings: ["ストックマーク"], reason: ""),
        ], existing: UserDictionary(text: ""), material: "ストックマークの件")
        check("既定の絞り込み: 材料にない読みは除き、表記も材料になければ候補ごと除く", !legacy.contains { $0.spelling == "J3" })
        check("既定の絞り込み: 材料にある読みなら、表記が材料になくても残す", legacy.first { $0.spelling == "Stockmark" }?.readings == ["ストックマーク"])

        // 設計判断: DEC-DIC-234（共有の例。Windows の ScreenDictionaryTests と同じもの）
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("common/testdata/logic/screen-terms.json")
        struct Shared: Decodable {
            struct TermCase: Decodable { var line: String; var terms: [String] }
            var terms: [TermCase]
        }
        if let data = try? Data(contentsOf: url), let shared = try? JSONDecoder().decode(Shared.self, from: data) {
            for c in shared.terms {
                check("共有の例: \(c.line)", ScreenSnapshotLayout.terms(in: c.line) == c.terms)
            }
        } else {
            check("共有の例を読む（リポジトリの上で動かす）: \(url.path)", false)
        }

        // 設計判断: DEC-DIC-231（選んだ読みだけを足す）
        let model = ScreenDictionaryModel(settings: .shared, phase: .results(found))
        if let j3 {
            model.setChecked(j3, true)
            model.setReadingChecked(j3, "ジェイスリー", false)
            check("選ぶ: 外した読みは足さない", model.chosen.first?.readings == ["Jスリー"])
            check("選ぶ: 足す行は `読み => 表記`", DictionarySuggester.appending(model.chosen, to: "") == "Jスリー => J3")
            model.setChecked(j3, false)
            model.setChecked(j3, true)
            check("選ぶ: 候補を選び直すと読みはすべて選ばれる", model.chosen.first?.readings == ["Jスリー", "ジェイスリー"])
        }
        // 足した辞書で、話した形が表記になる（受け入れ条件 7 の決定的な部分）
        let added = UserDictionary(text: DictionarySuggester.appending(model.chosen, to: ""))
        check("足した辞書で「Jスリーの件ですが」が「J3の件ですが」になる", added.apply(to: "Jスリーの件ですが") == "J3の件ですが")

        print(failures == 0 ? "すべて OK" : "NG が \(failures) 件")
        return failures == 0
    }

    // MARK: - 画面

    private static func render(to dir: URL) throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let material = DictionarySuggester.ScreenMaterial(
            terms: ["J3", "Kubernetes", "Anews", "ストックマーク", "営業部", "v2.1"],
            lines: ["J3 の進捗（v2.1）", "Kubernetes のクラスタを移行", "株式会社ストックマーク 営業部 佐藤"],
            truncated: false)
        let samples = [
            DictionaryCandidate(spelling: "J3", readings: ["Jスリー", "ジェイスリー"], reason: "型番。話すとカタカナが混ざりやすい"),
            DictionaryCandidate(spelling: "Kubernetes", readings: ["クバネティス", "クーベネティス"], reason: "製品名"),
            DictionaryCandidate(spelling: "佐藤", readings: [], reason: "人の名前"),
        ]
        func write(_ phase: ScreenDictionaryModel.Phase, _ name: String, setup: (ScreenDictionaryModel) -> Void = { _ in }) throws {
            let model = ScreenDictionaryModel(settings: .shared, phase: phase)
            model.displays = 2
            setup(model)
            try MeetingNotesPreview.write(ScreenDictionaryView(model: model, close: {}), to: dir.appendingPathComponent(name))
        }
        try write(.needsPermission(meetingBusy: false), "permission.png")
        try write(.needsPermission(meetingBusy: true), "permission-meeting.png")
        try write(.reading, "reading.png")
        try write(.ready(material), "ready.png")
        var cut = material
        cut.truncated = true
        try write(.ready(cut), "ready-truncated.png")
        try write(.searching(material), "searching.png")
        try write(.results(samples), "candidates.png") { model in
            model.model = "gemini-3.8-flash"
            model.setChecked(samples[0], true)
            model.setReadingChecked(samples[0], "ジェイスリー", false)
        }
        try write(.results([]), "empty.png")
        try write(.failed(tr("画面から文字を読み取れませんでした。")), "error.png")
        try write(.added(2), "added.png")
        print("wrote: \(dir.path)")
    }
}

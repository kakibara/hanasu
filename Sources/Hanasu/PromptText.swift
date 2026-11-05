import Foundation

// 要件: REQ-COM-022
// 設計判断: DEC-COM-054
/// プロンプトに埋め込む、ユーザー由来の文章（音声入力の認識結果・会議の文字起こし・本人のメモ・議事録）の下ごしらえ。
/// 文章の中に「</transcript>」などの区切りのタグがあると、区切りの外（指示の側）に文を置けてしまうので、
/// 区切りに使うタグだけを全角の山かっこ（＜/transcript＞）に置き換える。見た目の意味は変わらず、
/// Gemini・Claude・ローカルの LLM・Apple のどれにも効く。
/// Windows 版の `PromptText.NeutralizeDelimiters` と同じ考え。Mac には会議への質問（MeetingAsk）があるので、
/// そこで区切りに使う `<meeting>` `<minutes>` `<transcript_excerpts>` `<question>`、会議中の AI チャット（MeetingChat）の `<pending_transcript>` `<conversation>` `<user>` `<assistant>` も対象にする（そのぶん Windows より広い）。
/// 選択を声で編集するモードは、毎回変わる名前のタグ（DEC-DIC-033）で守るので、ここは使わない。
enum PromptText {
    /// 区切りに使うタグ。閉じタグ（`</…>`）、空白入り（`< / transcript >`）、大文字、属性つき（`<meeting id="M1">`）も拾う
    private static let delimiterTag = try! NSRegularExpression(
        pattern: #"<\s*(/?)\s*(transcript|transcript_excerpts|pending_transcript|user_notes|action_items|speaker_names|meeting|minutes|question|conversation|user|assistant)(\s[^<>]*?)??\s*>"#,
        options: [.caseInsensitive])

    static func neutralizeDelimiters(_ text: String) -> String {
        guard text.contains("<") else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return delimiterTag.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "＜$1$2$3＞")
    }
}

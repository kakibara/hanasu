import Foundation

/// 選択した文章を、声の指示どおりに Gemini で書き換える（選択を声で編集するモード）。
extension GeminiClient {
    struct EditRequest {
        /// 書き換える対象（最前面アプリで選択していた文章）
        var selection: String
        /// 話した指示の認識結果（「もっと丁寧に」「英語にして」など）
        var instruction: String
        var model: String
        var appName: String?
        var dictionary: [String]
    }

    // 要件: REQ-COM-061
    /// 編集の指示（文面は Resources/Prompts/<言語>.json の edit.system）
    static var editInstruction: String { Prompts.text("edit.system") }

    // 設計判断: DEC-DIC-033
    /// 選択文と指示を、毎回変わる名前のタグで囲む。選択文の中に閉じタグを書いて抜け出す、という手口を防ぐため。
    static func editPrompt(for request: EditRequest, nonce: String = makeNonce()) -> String {
        let selectionTag = "selection_\(nonce)"
        let instructionTag = "instruction_\(nonce)"
        // ランダムな文字列なので偶然は一致しないが、念のため中身から同じタグを取り除く
        func sanitize(_ text: String) -> String {
            [selectionTag, instructionTag].reduce(text) { text, tag in
                text.replacingOccurrences(of: "<\(tag)>", with: "").replacingOccurrences(of: "</\(tag)>", with: "")
            }
        }
        var lines: [String] = []
        if let appName = request.appName, !appName.isEmpty {
            lines.append(Prompts.text("edit.user.appName", ["app": appName]))
        }
        if !request.dictionary.isEmpty {
            lines.append(Prompts.text("edit.user.dictionary", ["words": request.dictionary.joined(separator: ", ")]))
        }
        lines.append("<\(selectionTag)>\n\(sanitize(request.selection))\n</\(selectionTag)>")
        lines.append("<\(instructionTag)>\n\(sanitize(request.instruction))\n</\(instructionTag)>")
        // 最後にもう一度、従うのは指示だけだと念を押す（選択文の中の命令に引きずられないように）
        lines.append(Prompts.text("edit.user.reminder", ["instructionTag": instructionTag, "selectionTag": selectionTag]))
        return lines.joined(separator: "\n")
    }

    // 設計判断: DEC-DIC-033
    static func makeNonce() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
    }

    // 要件: REQ-DIC-050
    // 設計判断: DEC-DIC-034
    func editSelection(_ request: EditRequest) async throws -> String {
        let output = try await generate(
            systemInstruction: Self.editInstruction,
            userText: Self.editPrompt(for: request),
            model: request.model)
        return Self.stripCodeFence(output, selection: request.selection)
    }
    // Claude で書き換えるときも、同じ editInstruction・editPrompt・stripCodeFence を使う（TextAIClient.editSelection）

    // 設計判断: DEC-DIC-034
    /// 指示に反してコードブロックで囲んで返されたときは外す（選択文自体がコードブロックなら外さない）
    static func stripCodeFence(_ output: String, selection: String) -> String {
        guard output.hasPrefix("```"), output.hasSuffix("```"), output.count > 6,
              !selection.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```")
        else { return output }
        var lines = output.components(separatedBy: "\n")
        guard lines.count >= 3 else { return output }
        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

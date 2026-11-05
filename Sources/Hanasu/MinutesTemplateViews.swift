import AppKit
import SwiftUI

// 要件: REQ-MTG-017
/// 記録を始める前に議事録の型を選ぶ欄（会議ノートの左下）
struct MinutesTemplatePicker: View {
    @AppStorage(MinutesTemplateStore.templateKey) private var templateID = MinutesTemplate.auto.rawValue
    @AppStorage(MinutesTemplateStore.customPromptKey) private var customPrompt = MinutesTemplateStore.defaultCustomPrompt
    @State private var editing = false

    private var template: MinutesTemplate { MinutesTemplate(rawValue: templateID) ?? .auto }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(tr("議事録の型"), systemImage: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Picker(tr("議事録の型"), selection: $templateID) {
                    ForEach(MinutesTemplate.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                if template == .custom {
                    Button(tr("指示…")) { editing = true }
                }
            }
            .help(template.summary)
        }
        .sheet(isPresented: $editing) {
            CustomMinutesPromptSheet(prompt: customPrompt, actionLabel: tr("保存")) { customPrompt = $0 }
        }
    }
}

// 要件: REQ-MTG-017
/// 会議ノートで議事録の型を選び直して作り直すメニュー
struct MinutesTemplateMenu: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    @AppStorage(MinutesTemplateStore.customPromptKey) private var customPrompt = MinutesTemplateStore.defaultCustomPrompt
    @State private var pending: MinutesTemplate?
    @State private var editingCustom = false

    var body: some View {
        Menu {
            Section(tr("この型で議事録を作り直す")) {
                ForEach(MinutesTemplate.allCases) { template in
                    Button {
                        if template == .custom { editingCustom = true } else { pending = template }
                    } label: {
                        Label(template == meeting.template ? tr("%@（今の型）", "\(template.title)") : template.title,
                              systemImage: template.systemImage)
                    }
                }
            }
        } label: {
            Label(tr("型: %@", "\(meeting.template.title)"), systemImage: meeting.template.systemImage)
        }
        .fixedSize()
        .disabled(recorder.state != .idle || meeting.utterances.isEmpty)
        .help(tr("議事録の型を選び直して、議事録を作り直します"))
        .confirmationDialog(
            tr("議事録を「%@」の型で作り直しますか？", "\(pending?.title ?? "")"),
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
        ) {
            Button(tr("作り直す")) {
                if let template = pending { Task { await recorder.regenerateMinutes(meeting, template: template) } }
                pending = nil
            }
            Button(tr("キャンセル"), role: .cancel) { pending = nil }
        } message: {
            Text(tr("今の議事録とアクションアイテムは置き換わります。"))
        }
        .sheet(isPresented: $editingCustom) {
            CustomMinutesPromptSheet(prompt: meeting.customMinutesPrompt ?? customPrompt, actionLabel: tr("作り直す")) { prompt in
                customPrompt = prompt
                Task { await recorder.regenerateMinutes(meeting, template: .custom, customPrompt: prompt) }
            }
        }
    }
}

/// カスタムの型の指示を書くシート
struct CustomMinutesPromptSheet: View {
    @State var prompt: String
    let actionLabel: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("カスタムの議事録の型")).font(.headline)
            Text(tr("見出しの構成や書き方を自由に書いてください（例: 「## 顧客の要望」「## 宿題」の見出しで、箇条書きで短く）。アクションアイテム（担当・内容・期限）と話者のメモは、自動で最後に付きます。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            HStack {
                Button(tr("例に戻す")) { prompt = MinutesTemplateStore.defaultCustomPrompt }
                Spacer()
                Button(tr("キャンセル")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(actionLabel) {
                    onSave(prompt)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 480)
    }
}

// 要件: REQ-MTG-019
// 設計判断: DEC-MTG-066
/// 会議ノートの「書き出し」メニュー（コピー・ファイルに保存・リマインダー）
struct MeetingExportMenu: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    /// 文字起こしのタブを表示しているか（Markdown のコピーと保存は表示中の方を対象にする）
    let showingTranscript: Bool
    @State private var copied: String?
    @State private var showingReminders = false

    private var markdown: String { showingTranscript ? meeting.transcriptMarkdown() : (meeting.minutes ?? "") }
    private var kind: String { showingTranscript ? tr("文字起こし") : tr("議事録") }

    var body: some View {
        Menu {
            Section(kind) {
                Button(tr("Markdown でコピー")) { copy(markdown, note: tr("コピーしました")) }
                    .disabled(markdown.isEmpty)
                Button(tr("Markdown ファイルとして保存…")) { save(.markdown) }
                    .disabled(markdown.isEmpty)
                Button(tr("テキストファイルとして保存…")) { save(.text) }
                    .disabled(markdown.isEmpty)
            }
            Section(tr("議事録の共有")) {
                Button(tr("Slack 向けにコピー")) {
                    if let text = MeetingExport.slack(meeting) { copy(text, note: tr("Slack 向けにコピーしました")) }
                }
                .disabled(meeting.minutes == nil)
                Button(tr("アクションアイテムをリマインダーに登録…")) { showingReminders = true }
                    .disabled(meeting.resolvedActionItems.isEmpty)
            }
        } label: {
            Label(copied ?? tr("書き出し"), systemImage: copied == nil ? "square.and.arrow.up" : "checkmark")
        }
        .fixedSize()
        .sheet(isPresented: $showingReminders) {
            ReminderExportSheet(meeting: meeting, recorder: recorder)
        }
    }

    private func copy(_ text: String, note: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = note
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = nil }
    }

    private func save(_ format: MeetingExport.FileFormat) {
        MeetingExport.save(markdown, suggestedName: MeetingExport.suggestedFileName(
            for: meeting, transcript: showingTranscript, format: format), format: format)
    }
}

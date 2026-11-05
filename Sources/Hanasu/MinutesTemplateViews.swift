import AppKit
import SwiftUI

// 要件: REQ-MTG-017, REQ-MTG-042
/// 記録を始める前に議事録の型を選ぶ欄（会議ノートの左下）。保存したテンプレートも選べる
struct MinutesTemplatePicker: View {
    @AppStorage(MinutesTemplateStore.templateKey) private var templateID = MinutesTemplate.auto.rawValue
    @AppStorage(MinutesTemplateStore.customPromptKey) private var customPrompt = MinutesTemplateStore.defaultCustomPrompt
    @AppStorage(SavedMinutesTemplateStore.listKey) private var savedJSON = ""
    @State private var editing = false
    @State private var managing = false

    private var saved: [SavedMinutesTemplate] { SavedMinutesTemplateStore.decode(savedJSON) }
    private var savedSelection: SavedMinutesTemplate? {
        SavedMinutesTemplateStore.template(forSelection: templateID, in: saved)
    }
    private var template: MinutesTemplate { MinutesTemplate(rawValue: templateID) ?? .auto }
    /// 選んでいたテンプレートが消されていたら「自動」として見せる（記録を始めるときも「自動」になる）
    private var selection: Binding<String> {
        Binding(
            get: {
                templateID.hasPrefix(SavedMinutesTemplateStore.selectionPrefix) && savedSelection == nil
                    ? MinutesTemplate.auto.rawValue : templateID
            },
            set: { templateID = $0 })
    }
    private var help: String {
        if let savedSelection {
            return savedSelection.instructions.components(separatedBy: "\n").first ?? savedSelection.name
        }
        return template.summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("議事録の型", systemImage: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Picker("議事録の型", selection: selection) {
                    ForEach(MinutesTemplate.allCases) { Text($0.title).tag($0.rawValue) }
                    if !saved.isEmpty {
                        Divider()
                        ForEach(saved) { Text($0.name).tag(SavedMinutesTemplateStore.selection(for: $0)) }
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                if template == .custom, savedSelection == nil {
                    Button("指示…") { editing = true }
                }
                Button { managing = true } label: { Image(systemName: "list.bullet.rectangle") }
                    .help("保存したテンプレートを管理します")
            }
            .help(help)
        }
        .sheet(isPresented: $editing) {
            CustomMinutesPromptSheet(prompt: customPrompt, actionLabel: "保存") { customPrompt = $0 }
        }
        .sheet(isPresented: $managing) {
            MinutesTemplateManagerSheet()
        }
    }
}

// 要件: REQ-MTG-017, REQ-MTG-042
/// 会議ノートで議事録の型を選び直して作り直すメニュー
struct MinutesTemplateMenu: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    @AppStorage(MinutesTemplateStore.customPromptKey) private var customPrompt = MinutesTemplateStore.defaultCustomPrompt
    @AppStorage(SavedMinutesTemplateStore.listKey) private var savedJSON = ""
    @State private var pending: Pending?
    @State private var editingCustom = false
    @State private var managing = false

    /// 作り直しの確認待ちの型
    private struct Pending {
        var title: String
        var template: MinutesTemplate
        var prompt: String?
        var name: String?
    }

    private var saved: [SavedMinutesTemplate] { SavedMinutesTemplateStore.decode(savedJSON) }

    var body: some View {
        Menu {
            Section("この型で議事録を作り直す") {
                ForEach(MinutesTemplate.allCases) { template in
                    Button {
                        if template == .custom {
                            editingCustom = true
                        } else {
                            pending = Pending(title: template.title, template: template)
                        }
                    } label: {
                        let current = template == meeting.template
                            && !(template == .custom && meeting.minutesTemplateName != nil)
                        Label(current ? "\(template.title)（今の型）" : template.title, systemImage: template.systemImage)
                    }
                }
            }
            if !saved.isEmpty {
                Section("保存したテンプレート") {
                    ForEach(saved) { item in
                        Button {
                            pending = Pending(title: item.name, template: .custom, prompt: item.instructions, name: item.name)
                        } label: {
                            let current = meeting.template == .custom && meeting.minutesTemplateName == item.name
                            Label(current ? "\(item.name)（今の型）" : item.name, systemImage: "doc.text")
                        }
                    }
                }
            }
            Divider()
            Button("テンプレートを管理…") { managing = true }
        } label: {
            Label("型: \(meeting.templateTitle)", systemImage: meeting.template.systemImage)
        }
        .fixedSize()
        .disabled(recorder.state != .idle || meeting.utterances.isEmpty)
        .help("議事録の型を選び直して、議事録を作り直します")
        .confirmationDialog(
            "議事録を「\(pending?.title ?? "")」の型で作り直しますか？",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
        ) {
            Button("作り直す") {
                if let pending {
                    Task {
                        await recorder.regenerateMinutes(
                            meeting, template: pending.template, customPrompt: pending.prompt, templateName: pending.name)
                    }
                }
                pending = nil
            }
            Button("キャンセル", role: .cancel) { pending = nil }
        } message: {
            Text("今の議事録とアクションアイテムは置き換わります。")
        }
        .sheet(isPresented: $editingCustom) {
            CustomMinutesPromptSheet(prompt: meeting.customMinutesPrompt ?? customPrompt, actionLabel: "作り直す") { prompt in
                customPrompt = prompt
                Task { await recorder.regenerateMinutes(meeting, template: .custom, customPrompt: prompt) }
            }
        }
        .sheet(isPresented: $managing) {
            MinutesTemplateManagerSheet()
        }
    }
}

// 要件: REQ-MTG-042
/// カスタムの型の指示を書くシート。書いた指示は、名前を付けてテンプレートとして保存できる
struct CustomMinutesPromptSheet: View {
    @State var prompt: String
    let actionLabel: String
    let onSave: (String) -> Void
    @AppStorage(SavedMinutesTemplateStore.listKey) private var savedJSON = ""
    @State private var askingName = false
    @State private var newName = ""
    @State private var savedNote: String?
    @Environment(\.dismiss) private var dismiss

    private var emptyPrompt: Bool { prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("カスタムの議事録の型").font(.headline)
            Text("見出しの構成や書き方を自由に書いてください（例: 「## 顧客の要望」「## 宿題」の見出しで、箇条書きで短く）。アクションアイテム（担当・内容・期限）と話者のメモは、自動で最後に付きます。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            if let savedNote {
                Text(savedNote).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("例に戻す") { prompt = MinutesTemplateStore.defaultCustomPrompt }
                Button("テンプレートとして保存…") {
                    newName = SavedMinutesTemplateStore.uniqueName(
                        from: "新しいテンプレート", in: SavedMinutesTemplateStore.decode(savedJSON))
                    askingName = true
                }
                .disabled(emptyPrompt)
                Spacer()
                Button("キャンセル") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(actionLabel) {
                    onSave(prompt)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(emptyPrompt)
            }
        }
        .padding()
        .frame(width: 480)
        .alert("テンプレートの名前", isPresented: $askingName) {
            TextField("名前", text: $newName)
            Button("保存") { saveAsTemplate() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この指示を、名前を付けて保存します。記録の前や、議事録の作り直しで選べます。")
        }
    }

    private func saveAsTemplate() {
        var list = SavedMinutesTemplateStore.decode(savedJSON)
        if let problem = SavedMinutesTemplateStore.add(name: newName, instructions: prompt, to: &list) {
            savedNote = "保存できませんでした: \(problem.message)"
        } else {
            savedJSON = SavedMinutesTemplateStore.encode(list)
            savedNote = "「\(SavedMinutesTemplateStore.trimmedName(newName))」として保存しました"
        }
    }
}

// 要件: REQ-MTG-042
// 設計判断: DEC-MTG-076
/// 保存したテンプレートの管理（一覧・追加・名前と指示の編集・複製・削除）。
/// 名前と指示は、保存できる内容なら直すたびに自動で保存する（保存ボタンはない）。
struct MinutesTemplateManagerSheet: View {
    @AppStorage(SavedMinutesTemplateStore.listKey) private var savedJSON = ""
    @State private var selection: UUID?
    @State private var name = ""
    @State private var instructions = ""
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    private var list: [SavedMinutesTemplate] { SavedMinutesTemplateStore.decode(savedJSON) }
    private var problem: SavedMinutesTemplateStore.Problem? {
        guard let selection else { return nil }
        return SavedMinutesTemplateStore.problem(name: name, instructions: instructions, in: list, excluding: selection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("議事録のテンプレート").font(.headline)
            Text("見出しの構成や書き方の指示に名前を付けて保存します。記録の前や、議事録の作り直しで選べます。アクションアイテムと話者のメモは、自動で最後に付きます。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 6) {
                    List(list, selection: $selection) { Text($0.name) }
                        .frame(width: 170, height: 240)
                        .overlay {
                            if list.isEmpty {
                                Text("まだありません").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    HStack {
                        Button { add() } label: { Image(systemName: "plus") }
                            .help("新しいテンプレートを追加")
                        Button { duplicate() } label: { Image(systemName: "plus.square.on.square") }
                            .help("選んでいるテンプレートを複製")
                            .disabled(selection == nil)
                        Button { confirmingDelete = true } label: { Image(systemName: "trash") }
                            .help("選んでいるテンプレートを削除")
                            .disabled(selection == nil)
                        Spacer()
                    }
                }
                if selection != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("名前", text: $name)
                            .textFieldStyle(.roundedBorder)
                        TextEditor(text: $instructions)
                            .font(.body)
                            .frame(minHeight: 180)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                        if let problem {
                            Text("\(problem.message)（このままでは保存されません）")
                                .font(.caption).foregroundStyle(.red)
                        } else {
                            Text("変更は自動で保存されます").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("左の一覧から選ぶか、＋で追加してください")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            HStack {
                Spacer()
                Button("閉じる") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 640)
        .onAppear {
            selection = list.first?.id
            load()
        }
        .onChange(of: selection) { load() }
        .onChange(of: name) { commit() }
        .onChange(of: instructions) { commit() }
        .confirmationDialog(
            "「\(list.first { $0.id == selection }?.name ?? "")」を削除しますか？",
            isPresented: $confirmingDelete
        ) {
            Button("削除", role: .destructive) { remove() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("このテンプレートで作った会議の議事録は、そのまま残ります。")
        }
    }

    /// 選んだテンプレートの内容を編集欄に読み込む
    private func load() {
        guard let item = list.first(where: { $0.id == selection }) else {
            name = ""
            instructions = ""
            return
        }
        name = item.name
        instructions = item.instructions
    }

    /// 保存できる内容なら保存する（保存できないときは、画面に理由を出して保存しない）
    private func commit() {
        guard let selection else { return }
        var items = list
        if SavedMinutesTemplateStore.update(id: selection, name: name, instructions: instructions, in: &items) == nil {
            let encoded = SavedMinutesTemplateStore.encode(items)
            if encoded != savedJSON { savedJSON = encoded }
        }
    }

    private func add() {
        var items = list
        let newName = SavedMinutesTemplateStore.uniqueName(from: "新しいテンプレート", in: items)
        guard SavedMinutesTemplateStore.add(name: newName, instructions: MinutesTemplateStore.defaultCustomPrompt, to: &items) == nil
        else { return }
        savedJSON = SavedMinutesTemplateStore.encode(items)
        selection = items.last?.id
    }

    private func duplicate() {
        guard let selection else { return }
        var items = list
        guard let copy = SavedMinutesTemplateStore.duplicate(id: selection, in: &items) else { return }
        savedJSON = SavedMinutesTemplateStore.encode(items)
        self.selection = copy
    }

    private func remove() {
        guard let selection else { return }
        var items = list
        SavedMinutesTemplateStore.remove(id: selection, from: &items)
        savedJSON = SavedMinutesTemplateStore.encode(items)
        self.selection = items.first?.id
        load()
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
    private var kind: String { showingTranscript ? "文字起こし" : "議事録" }

    var body: some View {
        Menu {
            Section(kind) {
                Button("Markdown でコピー") { copy(markdown, note: "コピーしました") }
                    .disabled(markdown.isEmpty)
                Button("Markdown ファイルとして保存…") { save(.markdown) }
                    .disabled(markdown.isEmpty)
                Button("テキストファイルとして保存…") { save(.text) }
                    .disabled(markdown.isEmpty)
            }
            Section("議事録の共有") {
                Button("Slack 向けにコピー") {
                    if let text = MeetingExport.slack(meeting) { copy(text, note: "Slack 向けにコピーしました") }
                }
                .disabled(meeting.minutes == nil)
                Button("アクションアイテムをリマインダーに登録…") { showingReminders = true }
                    .disabled(meeting.resolvedActionItems.isEmpty)
            }
        } label: {
            Label(copied ?? "書き出し", systemImage: copied == nil ? "square.and.arrow.up" : "checkmark")
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

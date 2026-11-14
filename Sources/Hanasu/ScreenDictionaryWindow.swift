import AppKit
import SwiftUI

// 画面から辞書の候補を探す（REQ-DIC-075）。
// メニューから選ぶと、すべての画面を撮って文字を読み、AI に送る材料を見せてから、「候補を探す」を押したときだけ送る。
// 画像は OCR が終わったら捨て、読んだ文字はこの画面を閉じるまでメモリの上だけに置く。

// MARK: - 状態

// 要件: REQ-DIC-075
// 設計判断: DEC-DIC-231, DEC-DIC-232, DEC-DIC-233, DEC-DIC-236
@MainActor
final class ScreenDictionaryModel: ObservableObject {
    enum Phase: Equatable {
        /// 画面収録の許可がない。meetingBusy なら、会議の記録中・作り直し中なので求めなかった
        case needsPermission(meetingBusy: Bool)
        case reading
        /// 読み終えた。送る材料を見せて「候補を探す」を待つ
        case ready(DictionarySuggester.ScreenMaterial)
        case searching(DictionarySuggester.ScreenMaterial)
        case results([DictionaryCandidate])
        case failed(String)
        /// 追加した（知らせを出して閉じる）
        case added(Int)
    }

    @Published var phase: Phase
    /// 撮った画面の数
    @Published var displays = 0
    /// チェックした候補
    @Published var checked: Set<UUID> = []
    /// チェックした候補のうち、外した読み
    @Published var uncheckedReadings: [UUID: Set<String>] = [:]
    /// 候補を探したモデルの名前
    @Published var model = ""

    let settings: AppSettings
    /// 閉じるとき（追加したあと）に呼ぶ
    var onClose: () -> Void = {}
    private var task: Task<Void, Never>?

    init(settings: AppSettings, phase: Phase = .reading) {
        self.settings = settings
        self.phase = phase
    }

    /// 送り先の AI（設定の「AI」の「議事録」。DEC-COM-040）
    var provider: TextAIProvider { settings.aiProvider(for: .meeting) }
    var destination: String {
        let model = settings.textModel(for: .meeting)
        return model.isEmpty ? provider.label : tr("%@（%@）", provider.label, model)
    }

    var candidates: [DictionaryCandidate] {
        if case .results(let found) = phase { return found }
        return []
    }

    // 設計判断: DEC-DIC-230, DEC-DIC-231
    /// 撮った画面を読み、送る材料を作る
    func read(_ shots: [ScreenSnapshotReader.Shot], languages: [String]) {
        phase = .reading
        displays = shots.count
        task = Task {
            let started = Date()
            do {
                let lines = try await ScreenSnapshotReader.recognizeAll(shots, languages: languages)
                try Task.checkCancellation()
                let existing = settings.userDictionary
                // 上限は送り先の AI で決める。AI が使えなければ（鍵がないなど）Gemini・Claude の上限で作り、探すときに理由を出す
                let budget = (try? TextAIClient.requireFromSettings(settings, for: .meeting)).map {
                    DictionarySuggester.budget(for: $0, existing: existing, instruction: DictionarySuggester.screenInstruction)
                } ?? .characters(DictionarySuggester.characterLimit)
                let material = DictionarySuggester.screenMaterial(lines, budget: budget)
                appLog.notice("screen dictionary: read \(shots.count, privacy: .public) displays, \(lines.count, privacy: .public) lines -> terms=\(material.terms.count, privacy: .public) lines=\(material.lines.count, privacy: .public) chars=\(material.text.count, privacy: .public) truncated=\(material.truncated, privacy: .public), \(Date().timeIntervalSince(started), format: .fixed(precision: 2), privacy: .public)s")
                phase = material.isEmpty ? .failed(tr("画面から文字を読み取れませんでした。")) : .ready(material)
            } catch is CancellationError {
                // 閉じたので何もしない
            } catch {
                appLog.notice("screen dictionary: read failed (\(error.localizedDescription, privacy: .public))")
                if !Task.isCancelled { phase = .failed(error.localizedDescription) }
            }
        }
    }

    // 要件: REQ-DIC-075
    // 設計判断: DEC-DIC-232, DEC-DIC-236
    /// 「候補を探す」を押したときだけ、見せた材料を送る。ローカルのモデルがなくても、ダウンロードは尋ねない
    func search() {
        guard case .ready(let material) = phase else { return }
        phase = .searching(material)
        task = Task {
            let started = Date()
            do {
                let client = try TextAIClient.requireFromSettings(settings, for: .meeting)
                let modelName = settings.textModel(for: .meeting)
                let found = try await DictionarySuggester.suggestFromScreen(
                    material, existing: settings.userDictionary, client: client, model: modelName)
                try Task.checkCancellation()
                appLog.notice("screen dictionary: sent, \(found.count, privacy: .public) candidates, \(Date().timeIntervalSince(started), format: .fixed(precision: 2), privacy: .public)s")
                model = modelName
                checked = []
                uncheckedReadings = [:]
                phase = .results(found)
            } catch is CancellationError {
                // 閉じたので何もしない
            } catch {
                appLog.notice("screen dictionary: search failed (\(error.localizedDescription, privacy: .public))")
                if !Task.isCancelled { phase = .failed(error.localizedDescription) }
            }
        }
    }

    /// 作業を止める（閉じたとき）
    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: 選ぶ

    func isChecked(_ candidate: DictionaryCandidate) -> Bool { checked.contains(candidate.id) }

    /// 候補をチェックすると、その読みもすべてチェックされる
    func setChecked(_ candidate: DictionaryCandidate, _ on: Bool) {
        if on { checked.insert(candidate.id) } else { checked.remove(candidate.id) }
        uncheckedReadings[candidate.id] = nil
    }

    func isReadingChecked(_ candidate: DictionaryCandidate, _ reading: String) -> Bool {
        isChecked(candidate) && !(uncheckedReadings[candidate.id]?.contains(reading) ?? false)
    }

    func setReadingChecked(_ candidate: DictionaryCandidate, _ reading: String, _ on: Bool) {
        guard isChecked(candidate) else { return }
        var off = uncheckedReadings[candidate.id] ?? []
        if on { off.remove(reading) } else { off.insert(reading) }
        uncheckedReadings[candidate.id] = off
    }

    /// 足すもの。チェックした候補に、チェックした読みだけを付ける
    var chosen: [DictionaryCandidate] {
        candidates.filter(isChecked).map { candidate in
            var candidate = candidate
            let off = uncheckedReadings[candidate.id] ?? []
            candidate.readings = candidate.readings.filter { !off.contains($0) }
            return candidate
        }
    }

    // 設計判断: DEC-DIC-087
    /// 選んだものを辞書の末尾に足し、知らせを出してから閉じる
    func add() {
        guard !chosen.isEmpty else { return }
        let chosen = DictionarySuggester.droppingRegistered(chosen, existing: settings.userDictionary)
        settings.dictionaryText = DictionarySuggester.appending(chosen, to: settings.dictionaryText)
        phase = .added(chosen.count)
        Task {
            try? await Task.sleep(for: .seconds(2))
            onClose()
        }
    }
}

// MARK: - 画面

// 要件: REQ-DIC-075
// 設計判断: DEC-DIC-232
struct ScreenDictionaryView: View {
    @ObservedObject var model: ScreenDictionaryModel
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("画面から辞書の候補を探す")).font(.headline)
            Divider()
            content
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
            Divider()
            Text(tr("画面に表示されている文字を、この Mac の中で読み取ります（画像は送らず、保存もしません）。Hanasu のウインドウ・除外アプリ（設定の「AI」→「画面の文脈」）・通知・認証のダイアログは写しません。ブラウザの中のパスワード管理の拡張や、ほかの画面のターミナルなどは写ります。読んだ文字は、「候補を探す」を押したときだけ、設定の「AI」で「議事録」に選んだ AI に送ります（「ローカル」なら、この Mac の外には送りません。「Apple」では、動いている間、同じ Mac のほかのユーザーにも見えることがあります）。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            buttons
        }
        .padding(20)
        .frame(width: 600)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .needsPermission(let meetingBusy):
            VStack(alignment: .leading, spacing: 8) {
                Text("⚠️ " + tr("画面収録の許可がありません。")).foregroundStyle(.orange)
                Text(meetingBusy
                     ? tr("会議の記録が終わってから許可してください（許可すると Hanasu を開き直すことになり、記録が切れるため）。")
                     : tr("画面収録を許可したら、Hanasu を終了して開き直し、もう一度選んでください。"))
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("システム設定を開く")) { Permissions.openPrivacySettings("Privacy_ScreenCapture") }
                    .disabled(meetingBusy)
            }
        case .reading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(tr("画面の文字を読んでいます…"))
            }
        case .ready(let material):
            materialView(material, searching: false)
        case .searching(let material):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(tr("探しています…"))
                }
                materialView(material, searching: true)
            }
        case .failed(let message):
            Text("⚠️ " + message).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        case .results(let found) where found.isEmpty:
            Text(tr("新しい候補は見つかりませんでした。")).foregroundStyle(.secondary)
        case .results(let found):
            VStack(alignment: .leading, spacing: 6) {
                Text(model.model.isEmpty ? tr("追加したいものを選んでください。") : tr("追加したいものを選んでください（%@）。", model.model))
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(found) { candidate in
                            ScreenDictionaryCandidateRow(candidate: candidate, model: model)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 340)
                .accessibilityLabel(tr("辞書の候補"))
            }
        case .added(let count):
            Label(tr("%@ 件を辞書に追加しました。", "\(count)"), systemImage: "checkmark.circle")
        }
    }

    /// 送る材料（見せたものと送るものは同じ。DEC-DIC-231）
    private func materialView(_ material: DictionarySuggester.ScreenMaterial, searching: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("%@ 画面から読み、語 %@ 個・行 %@ 行を送ります。", "\(model.displays)", "\(material.terms.count)", "\(material.lines.count)"))
            Text(tr("送り先: %@", model.destination)).font(.caption).foregroundStyle(.secondary)
            if model.provider == .local || model.provider == .appleFM {
                Text(tr("読みの推測は、Gemini・Claude のほうが確かです（設定の「AI」の「議事録」で変えられます）。"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if material.truncated {
                Label(tr("画面の文字が多いので、一部だけを送ります。"), systemImage: "scissors")
                    .font(.caption).foregroundStyle(.orange)
            }
            materialBox(tr("語"), material.terms.joined(separator: ", "))
            materialBox(tr("画面の行"), material.lines.joined(separator: "\n"))
        }
        .opacity(searching ? 0.6 : 1)
    }

    private func materialBox(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.bold())
            ScrollView {
                Text(text.isEmpty ? tr("（なし）") : text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .frame(height: 110)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            .accessibilityLabel(title)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack {
            Spacer()
            switch model.phase {
            case .ready:
                Button(tr("キャンセル"), role: .cancel, action: close)
                    .keyboardShortcut(.cancelAction)
                Button(tr("候補を探す"), action: model.search)
                    .keyboardShortcut(.defaultAction)
            case .results(let found) where !found.isEmpty:
                Button(tr("キャンセル"), role: .cancel, action: close)
                    .keyboardShortcut(.cancelAction)
                Button(tr("選んだ %@ 件を辞書に追加", "\(model.checked.count)"), action: model.add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.checked.isEmpty)
            case .reading, .searching:
                Button(tr("キャンセル"), role: .cancel, action: close)
                    .keyboardShortcut(.cancelAction)
            default:
                Button(tr("閉じる"), action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// 要件: REQ-DIC-075
// 設計判断: DEC-DIC-231
/// 画面からの候補の 1 行。表記と理由のチェックの下に、読みごとのチェックを並べる（読みは推測なので 1 つずつ外せる）
struct ScreenDictionaryCandidateRow: View {
    let candidate: DictionaryCandidate
    @ObservedObject var model: ScreenDictionaryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(isOn: Binding(get: { model.isChecked(candidate) }, set: { model.setChecked(candidate, $0) })) {
                Text(candidate.spelling).bold()
                if !candidate.reason.isEmpty { Text(candidate.reason) }
            }
            .toggleStyle(.checkbox)
            if candidate.readings.isEmpty {
                Text(tr("読みなし（語だけを登録します）"))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 20)
            } else {
                HStack(spacing: 10) {
                    Text(tr("読み:")).font(.caption).foregroundStyle(.secondary)
                    ForEach(candidate.readings, id: \.self) { reading in
                        Toggle(reading, isOn: Binding(
                            get: { model.isReadingChecked(candidate, reading) },
                            set: { model.setReadingChecked(candidate, reading, $0) }))
                            .toggleStyle(.checkbox)
                            .font(.caption)
                            .disabled(!model.isChecked(candidate))
                    }
                }
                .padding(.leading, 20)
            }
        }
    }
}

// MARK: - ウインドウ

// 要件: REQ-DIC-075
// 設計判断: DEC-DIC-230, DEC-DIC-232
/// 候補の画面のウインドウ。同時に 1 つだけで、開いていれば前に出す
@MainActor
final class ScreenDictionaryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: ScreenDictionaryModel?

    /// 開いていれば前に出して true
    func bringToFront() -> Bool {
        guard let window, window.isVisible else { return false }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func open(_ model: ScreenDictionaryModel) {
        self.model?.cancel()
        self.model = model
        // 追加して 2 秒後に閉じるとき、そのあいだに開き直した別の画面を閉じない
        model.onClose = { [weak self, weak model] in
            guard let self, let model, self.model === model else { return }
            self.close()
        }
        let window = Self.makeWindow(model: model, close: { [weak self] in self?.close() })
        window.delegate = self
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// 見た目の確認（--render-screen-dictionary）でも同じものを作る
    static func makeWindow(model: ScreenDictionaryModel, close: @escaping () -> Void) -> NSWindow {
        let hosting = NSHostingController(rootView: ScreenDictionaryView(model: model, close: close))
        let window = NSWindow(contentViewController: hosting)
        window.title = tr("Hanasu 画面から辞書の候補を探す")
        window.styleMask = [.titled, .closable]
        // 全画面表示のアプリの上で選んでも、その Space に開く（DEC-DIC-230）
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        return window
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // 閉じたら OCR と AI の呼び出しを止め、読んだ文字を捨てる
        model?.cancel()
        model = nil
        window = nil
    }
}

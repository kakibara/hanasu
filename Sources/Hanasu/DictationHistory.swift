import AppKit
@preconcurrency import AVFoundation
import Carbon.HIToolbox
import Combine
import Foundation

// 設計判断: DEC-DIC-071
/// 音声入力の履歴 1 件。
struct DictationHistoryEntry: Codable, Identifiable, Equatable {
    // 設計判断: DEC-DIC-029
    /// 保存する値は、整形が refine、英訳が今までの値（translate）、和訳が translateJapanese、ほかの言語への翻訳が translate:<言語のコード>。
    /// 知らない値は読み込みを止めず、値のまま残して書き戻す（Windows 版の HistoryMode と同じ）
    enum Mode: Hashable, Codable {
        case refine
        case translation(TranslationLanguage)
        /// この版の知らない値（新しい版が足した言語など）。値のまま残して書き戻す
        case unknown(String)

        init(_ mode: DictationController.Mode) {
            self = mode.translation.map(Self.init(translation:)) ?? .refine
        }

        init(translation: TranslationLanguage) {
            self = .translation(translation)
        }

        /// 保存した値から戻す。知らない値なら nil（ファイルから読むときは unknown にする）
        init?(rawValue: String) {
            switch rawValue {
            case "refine": self = .refine
            case "translate": self = .translation(.english)
            case "translateJapanese": self = .translation(.japanese)
            default:
                guard rawValue.hasPrefix("translate:"),
                      let language = PromptLanguage(rawValue: String(rawValue.dropFirst("translate:".count))) else { return nil }
                self = .translation(TranslationLanguage(language))
            }
        }

        var rawValue: String {
            switch self {
            case .refine: "refine"
            case .translation(.english): "translate"
            case .translation(.japanese): "translateJapanese"
            case .translation(let language): "translate:\(language.language.rawValue)"
            case .unknown(let value): value
            }
        }

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer().decode(String.self)
            self = Mode(rawValue: value) ?? .unknown(value)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        /// 翻訳の言語（整形なら nil）
        var translation: TranslationLanguage? {
            switch self {
            case .refine, .unknown: nil
            case .translation(let language): language
            }
        }

        /// 知らない値なら、その値（一覧にはそのまま出す）
        var unknownValue: String? {
            if case .unknown(let value) = self { value } else { nil }
        }

        var label: String { translation?.verb ?? unknownValue ?? tr("整形") }
    }

    enum Status: String, Codable {
        /// Gemini で整形（英訳）できた
        case succeeded
        /// Gemini がエラーになり、原文のまま入力した
        case geminiFailed
        /// 認証情報が未設定で、原文のまま入力した
        case noCredentials
        /// 整形をオフにしていて、原文のまま入力した
        case refineOff

        var label: String {
            switch self {
            case .succeeded: tr("成功")
            case .geminiFailed: tr("Gemini 失敗")
            case .noCredentials: tr("未設定のため原文のまま")
            case .refineOff: tr("整形オフ（原文のまま）")
            }
        }

        /// 一覧で「失敗・未整形」として印を付ける
        var isUnrefined: Bool { self != .succeeded }
        /// 失敗したもの（取り戻したい可能性が高い）
        var isFailure: Bool { self == .geminiFailed || self == .noCredentials }
    }

    var id = UUID()
    var date: Date
    /// 文字起こしの原文
    var raw: String
    /// 入力した結果（整形後・翻訳後。失敗時は原文と同じ）
    var output: String
    var mode: Mode
    /// 入力先アプリ
    var appName: String?
    var status: Status
    /// Gemini のエラー内容
    var errorMessage: String?
    /// 整形・英訳に使ったモデル
    var model: String?
    /// History/Audio/ にある録音のファイル名
    var audioFileName: String?
    /// 履歴ウインドウで整形・英訳し直した日時
    var retriedAt: Date?
    /// 「履歴を保存しない」設定のときの項目。ファイルには書かず、メモリ上だけに置く
    var transient = false

    private enum CodingKeys: String, CodingKey {
        case id, date, raw, output, mode, appName, status, errorMessage, model, audioFileName, retriedAt
    }
}

extension HotKeyCombo {
    /// 最後の結果をもう一度入力するショートカット
    static let defaultRepaste = HotKeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey | shiftKey))
}

// 要件: REQ-DIC-063
// 設計判断: DEC-DIC-073
/// 履歴の設定。AppSettings とは別の UserDefaults のキーで持つ。既定は 30 日・1000 件
final class HistorySettings: ObservableObject {
    static let shared = HistorySettings()

    static let countOptions = [100, 500, 1000, 5000]
    /// 0 は無期限
    static let dayOptions = [7, 30, 90, 365, 0]

    private let defaults = UserDefaults.standard

    /// 履歴をファイルに保存する
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Keys.enabled) } }
    /// 残す件数の上限
    @Published var maxCount: Int { didSet { defaults.set(maxCount, forKey: Keys.maxCount) } }
    /// 残す日数（0 は無期限）
    @Published var maxDays: Int { didSet { defaults.set(maxDays, forKey: Keys.maxDays) } }
    /// 録音した音声も残す
    @Published var keepAudio: Bool { didSet { defaults.set(keepAudio, forKey: Keys.keepAudio) } }
    @Published var repasteHotKey: HotKeyCombo {
        didSet {
            defaults.set(Int(repasteHotKey.keyCode), forKey: Keys.repasteHotKeyCode)
            defaults.set(Int(repasteHotKey.modifiers), forKey: Keys.repasteHotKeyModifiers)
        }
    }

    private init() {
        defaults.register(defaults: [
            Keys.enabled: true,
            Keys.maxCount: 1000,
            Keys.maxDays: 30,
            Keys.keepAudio: false,
            Keys.repasteHotKeyCode: Int(HotKeyCombo.defaultRepaste.keyCode),
            Keys.repasteHotKeyModifiers: Int(HotKeyCombo.defaultRepaste.modifiers),
        ])
        enabled = defaults.bool(forKey: Keys.enabled)
        maxCount = defaults.integer(forKey: Keys.maxCount)
        maxDays = defaults.integer(forKey: Keys.maxDays)
        keepAudio = defaults.bool(forKey: Keys.keepAudio)
        repasteHotKey = HotKeyCombo(
            keyCode: UInt32(defaults.integer(forKey: Keys.repasteHotKeyCode)),
            modifiers: UInt32(defaults.integer(forKey: Keys.repasteHotKeyModifiers)))
    }

    private enum Keys {
        static let enabled = "historyEnabled"
        static let maxCount = "historyMaxCount"
        static let maxDays = "historyMaxDays"
        static let keepAudio = "historyKeepAudio"
        static let repasteHotKeyCode = "repasteHotKeyCode"
        static let repasteHotKeyModifiers = "repasteHotKeyModifiers"
    }
}

enum DictationHistoryError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound: tr("履歴が見つかりません（削除された可能性があります）")
        }
    }
}

// 要件: REQ-DIC-060
/// 音声入力の履歴を ~/Library/Application Support/Hanasu/History/history.json に保存する。
/// 新しい順に持ち、件数と日数の上限を超えたものは古い順に消す（録音した音声も一緒に消す）。
@MainActor
final class DictationHistoryStore: ObservableObject {
    // 設計判断: DEC-DIC-070
    /// アプリで使う履歴。起動時に `preloadShared()` が裏で読んだ中身があればそれを使い、
    /// 先読みが終わる前に使われたら（メニュー・再入力・音声入力）、ここで同期で読む
    static let shared: DictationHistoryStore = {
        let store = DictationHistoryStore(directory: defaultDirectory)
        store.bind(to: HistorySettings.shared)
        if let preloaded = preloadedFile {
            store.load(from: preloaded)
        } else {
            store.load()
        }
        preloadedFile = nil
        store.flushOnTerminate()
        return store
    }()

    /// `preloadShared()` が裏で読んだ history.json の中身。`shared` を作るときに一度だけ使う
    private static var preloadedFile: FileReadResult?
    private static var preloadStarted = false

    // 設計判断: DEC-DIC-070
    /// 起動時に呼ぶ。history.json の読み込みとデコードを裏で行い、終わったらメインで `shared` を作る。
    /// それより前に `shared` が使われたときは、そちらが同期で読み、先読みの結果は捨てる
    /// （`shared` ができるまでは、アプリの中で history.json に書くものはないので、先読みの中身は古くならない）
    static func preloadShared() {
        guard !preloadStarted else { return }
        preloadStarted = true
        let fileURL = defaultDirectory.appendingPathComponent("history.json")
        Task { @MainActor in
            let result = await Task.detached(priority: .utility) { DictationHistoryStore.readFile(at: fileURL) }.value
            preloadedFile = result
            _ = shared  // まだ作っていなければ、読んだ中身で作る。作ってあれば何もしない
            preloadedFile = nil
        }
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hanasu/History", isDirectory: true)
    }

    /// 保存の方針。アプリでは HistorySettings から、確認用の CLI では直接決める
    struct Policy: Equatable {
        var enabled = true
        var maxCount = 1000
        var maxDays = 30
        var keepAudio = false
    }

    /// 保存しない設定のときに、メモリ上に置いておく件数（「最近の結果」と再入力のため）
    static let transientLimit = 10

    @Published private(set) var entries: [DictationHistoryEntry] = []
    /// 直近の保存・読み込みのエラー
    @Published private(set) var lastError: String?
    var policy = Policy() {
        didSet { if policy != oldValue, prune() { save() } }
    }

    /// 保存をまとめて遅らせる時間（秒）
    static let saveDelay: Double = 1

    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("history.json") }
    var audioDirectory: URL { directory.appendingPathComponent("Audio", isDirectory: true) }

    private var cancellables: Set<AnyCancellable> = []
    /// 書き込みの順番を守るための直列キュー。エンコードとファイル書き込みはここで行う
    private let writeQueue = DispatchQueue(label: "dev.hanasu.history-write", qos: .utility)
    /// まだファイルに書いていない変更がある
    private var saveDirty = false
    private var saveTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?

    init(directory: URL) {
        self.directory = directory
    }

    func bind(to settings: HistorySettings) {
        settings.$enabled.combineLatest(settings.$maxCount, settings.$maxDays, settings.$keepAudio)
            .map { Policy(enabled: $0, maxCount: $1, maxDays: $2, keepAudio: $3) }
            .removeDuplicates()
            .sink { [weak self] in self?.policy = $0 }
            .store(in: &cancellables)
    }

    // MARK: - 読み書き

    private struct FileContents: Codable {
        var version = 1
        var entries: [DictationHistoryEntry]
    }

    /// history.json を読んだ結果
    enum FileReadResult: Sendable {
        case missing
        case entries([DictationHistoryEntry])
        case failed(String)
    }

    /// history.json を読んでデコードする（どのスレッドからでも呼べる）
    nonisolated static func readFile(at fileURL: URL) -> FileReadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let contents = try decoder.decode(FileContents.self, from: Data(contentsOf: fileURL))
            return .entries(contents.entries)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // 設計判断: DEC-DIC-070
    func load() {
        flush()  // 書いていない変更があれば先に書く（読み直しで失わないように）
        load(from: Self.readFile(at: fileURL))
    }

    // 設計判断: DEC-DIC-070
    /// 読んだ中身を当てる。メモリだけの履歴（保存しない設定のもの）は残す
    private func load(from result: FileReadResult) {
        let transient = entries.filter(\.transient)
        switch result {
        case .missing:
            entries = transient
        case .entries(let saved):
            entries = (saved + transient).sorted { $0.date > $1.date }
        case .failed(let message):
            appLog.error("history load error: \(message, privacy: .public)")
            lastError = tr("履歴を読み込めませんでした: %@", "\(message)")
            return  // 壊れたファイルを上書きしないよう、ここで止める
        }
        lastError = nil
        if prune() { save() }
        removeOrphanAudio()
    }

    // 設計判断: DEC-DIC-070
    /// 保存を予約する。続けて呼ばれても、`saveDelay` 秒あとに 1 回だけ、その時点の中身を書く
    func save() {
        saveDirty = true
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.saveDelay))
            guard !Task.isCancelled else { return }
            self?.writeNow(wait: false)
        }
    }

    /// 予約している保存があれば、今すぐ書き終えてから返す（終了時・読み直しの前・確認用 CLI）
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard saveDirty else {
            writeQueue.sync {}  // 書き込み中のものがあれば終わるのを待つ
            return
        }
        writeNow(wait: true)
    }

    /// アプリを終えるときに、予約中の保存を書き切る
    func flushOnTerminate() {
        guard terminationObserver == nil else { return }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    /// 今の中身を書く。エンコードとファイル書き込みは直列キューで行うので、書く順番は予約した順のまま
    private func writeNow(wait: Bool) {
        saveTask = nil
        saveDirty = false
        let snapshot = entries.filter { !$0.transient }
        let directory = directory
        let fileURL = fileURL
        let work: @Sendable () -> String? = {
            Self.write(snapshot, directory: directory, fileURL: fileURL)
        }
        if wait {
            lastError = writeQueue.sync(execute: work)
        } else {
            writeQueue.async { [weak self] in
                let error = work()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.lastError = error }
                }
            }
        }
    }

    /// 書き込み本体（どのスレッドからでも呼べる）。失敗したときはエラーの文を返す
    private nonisolated static func write(_ entries: [DictationHistoryEntry], directory: URL, fileURL: URL) -> String? {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(FileContents(entries: entries))
            try data.write(to: fileURL, options: .atomic)
            // 話した内容が入っているので、本人だけが読めるようにする
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return nil
        } catch {
            appLog.error("history save error: \(error.localizedDescription, privacy: .public)")
            return tr("履歴を保存できませんでした: %@", "\(error.localizedDescription)")
        }
    }

    // MARK: - 追加・更新・削除

    /// 録音を残す設定なら、これから録る音声の保存先を返す
    func newAudioURL() -> URL? {
        guard policy.enabled, policy.keepAudio else { return nil }
        do {
            try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            appLog.error("history audio dir error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return audioDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
    }

    /// 使わなかった録音（取り消し・エラー）を消す
    func discardAudio(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // 設計判断: DEC-DIC-072, DEC-DIC-074
    @discardableResult
    func record(
        raw: String, output: String, mode: DictationHistoryEntry.Mode, appName: String?,
        status: DictationHistoryEntry.Status, errorMessage: String? = nil, model: String? = nil,
        audioURL: URL? = nil, date: Date = Date()
    ) -> DictationHistoryEntry {
        // ファイルには秒単位で書くので、メモリ上もそろえておく
        var entry = DictationHistoryEntry(
            date: Self.wholeSeconds(date), raw: raw, output: output, mode: mode, appName: appName,
            status: status, errorMessage: errorMessage, model: model)
        if policy.enabled {
            if let audioURL, FileManager.default.fileExists(atPath: audioURL.path) {
                entry.audioFileName = audioURL.lastPathComponent
            }
        } else {
            entry.transient = true
            discardAudio(audioURL)
        }
        // 新しい順を保ったまま、日時の合う位置に入れる（ふつうは先頭）
        entries.insert(entry, at: entries.firstIndex { $0.date <= entry.date } ?? entries.count)
        prune()
        if !entry.transient { save() }
        return entry
    }

    private static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    func delete(_ ids: Set<UUID>) {
        let removed = entries.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        entries.removeAll { ids.contains($0.id) }
        removed.forEach(removeAudio(of:))
        save()
    }

    func deleteAll() {
        entries.forEach(removeAudio(of:))
        entries.removeAll()
        save()
    }

    /// 録音した音声だけをすべて消す（文字の履歴は残す）
    func deleteAllAudio() {
        try? FileManager.default.removeItem(at: audioDirectory)
        for index in entries.indices { entries[index].audioFileName = nil }
        save()
    }

    func audioURL(for entry: DictationHistoryEntry) -> URL? {
        guard let name = entry.audioFileName else { return nil }
        let url = audioDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 残している録音の合計サイズ（バイト）と件数
    func audioUsage() -> (bytes: Int64, count: Int) {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: audioDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let bytes = urls.reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return (bytes, urls.count)
    }

    // 設計判断: DEC-DIC-073
    /// 上限を超えた履歴を消す。消したものがあれば true
    @discardableResult
    private func prune(now: Date = Date()) -> Bool {
        var kept: [DictationHistoryEntry] = []
        var removed: [DictationHistoryEntry] = []
        let cutoff = policy.maxDays > 0 ? now.addingTimeInterval(-Double(policy.maxDays) * 86400) : nil
        var persistentCount = 0
        var transientCount = 0
        for entry in entries {  // 新しい順
            let keep: Bool
            if entry.transient {
                transientCount += 1
                keep = transientCount <= Self.transientLimit
            } else if let cutoff, entry.date < cutoff {
                keep = false
            } else {
                persistentCount += 1
                keep = persistentCount <= max(1, policy.maxCount)
            }
            if keep { kept.append(entry) } else { removed.append(entry) }
        }
        guard !removed.isEmpty else { return false }
        entries = kept
        removed.forEach(removeAudio(of:))
        return true
    }

    private func removeAudio(of entry: DictationHistoryEntry) {
        guard let name = entry.audioFileName else { return }
        try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(name))
    }

    // 設計判断: DEC-DIC-075
    /// どの履歴からも参照されていない録音を消す（起動時の読み込みで呼ぶ）
    private func removeOrphanAudio() {
        let referenced = Set(entries.compactMap(\.audioFileName))
        let urls = (try? FileManager.default.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in urls where !referenced.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - 整形・英訳のやり直し

    // 要件: REQ-DIC-061
    // 設計判断: DEC-DIC-076
    /// 原文から AI（音声入力に選んだもの）を呼び直し、結果でこの履歴を上書きする。失敗したときは履歴を変えずにエラーを投げる
    @discardableResult
    func retry(_ id: UUID, mode: DictationHistoryEntry.Mode, client overrideClient: TextAIClient? = nil) async throws
        -> DictationHistoryEntry
    {
        guard let entry = entries.first(where: { $0.id == id }) else { throw DictationHistoryError.notFound }
        let settings = AppSettings.shared
        if overrideClient == nil {
            // 要件: REQ-COM-032
            try await LocalModelDownloadPrompt.prepare(
                for: .dictation, settings: settings, work: tr("やり直し"), whenSkipped: tr("やり直しません"))
        }
        let client = try overrideClient ?? TextAIClient.requireFromSettings(settings, for: .dictation)
        let model = settings.textModel(for: .dictation)
        let request = GeminiClient.Request(
            transcript: entry.raw,
            model: model,
            appName: settings.sendAppName ? entry.appName : nil,
            dictionary: settings.dictionaryWords,
            extraInstructions: settings.extraInstructions,
            outputLanguage: settings.refineOutputLanguage)
        let output = if let translation = mode.translation {
            try await client.translate(request, to: translation)
        } else {
            try await client.refine(request)
        }
        // 待っている間に消された場合
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw DictationHistoryError.notFound }
        entries[index].output = output
        entries[index].mode = mode
        entries[index].status = .succeeded
        entries[index].errorMessage = nil
        entries[index].model = model
        entries[index].retriedAt = Self.wholeSeconds(Date())
        if !entries[index].transient { save() }
        return entries[index]
    }
}

// 設計判断: DEC-DIC-075
/// 録音した音声を m4a に書き出す。オーディオのタップから書き、止めるときに閉じる。
final class DictationAudioWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?

    init(url: URL, format: AVAudioFormat) throws {
        file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: 32000,
            ],
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved)
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            do {
                try file?.write(from: buffer)
            } catch {
                appLog.error("dictation audio write error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func close() {
        lock.withLock {
            file?.close()
            file = nil
        }
    }
}

import AppKit
import EventKit
import SwiftUI

// 要件: REQ-MTG-019
// 設計判断: DEC-MTG-067
/// アクションアイテムをリマインダー（EventKit）に登録する。
/// 権限はユーザーが「登録」を押したときに初めて求める（シートを開いただけでは求めない）。
@MainActor
enum ReminderExporter {
    private static let store = EKEventStore()

    static var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .reminder) }
    static var isAuthorized: Bool { status == .fullAccess }

    /// 必要なら権限を求める。許可されていれば true。
    static func ensureAccess() async throws -> Bool {
        switch status {
        case .fullAccess: return true
        case .notDetermined: return try await store.requestFullAccessToReminders()
        default: return false
        }
    }

    /// 登録先のリスト（権限がないときは空。権限を求めない）
    static func lists() -> [EKCalendar] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .reminder).filter(\.allowsContentModifications)
    }

    static var defaultList: EKCalendar? {
        isAuthorized ? store.defaultCalendarForNewReminders() : nil
    }

    static func list(withID id: String) -> EKCalendar? {
        isAuthorized ? store.calendar(withIdentifier: id) : nil
    }

    /// 選んだアクションアイテムを登録し、アイテムの ID → リマインダーの識別子を返す
    static func add(_ items: [ActionItem], meeting: Meeting, to list: EKCalendar?) throws -> [UUID: String] {
        guard let calendar = list ?? store.defaultCalendarForNewReminders() else {
            throw NSError(domain: "Hanasu", code: 1, userInfo: [NSLocalizedDescriptionKey: "登録先のリマインダーのリストがありません"])
        }
        var ids: [UUID: String] = [:]
        var reminders: [EKReminder] = []
        for item in items {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
            reminder.title = item.task
            reminder.notes = notes(for: item, meeting: meeting)
            if let due = item.dueDate {
                // 時刻は決まっていないので日付だけ（終日）
                reminder.dueDateComponents = Calendar.current.dateComponents([.calendar, .year, .month, .day], from: due)
            }
            try store.save(reminder, commit: false)
            reminders.append(reminder)
            ids[item.id] = reminder.calendarItemIdentifier
        }
        try store.commit()
        return ids
    }

    static func notes(for item: ActionItem, meeting: Meeting) -> String {
        var lines: [String] = []
        if let owner = item.owner { lines.append("担当: \(owner)") }
        if let note = item.dueNote { lines.append("期限: \(note)") }
        lines.append("会議: \(meeting.title)（\(Meeting.dateFormatter.string(from: meeting.startedAt))）")
        return lines.joined(separator: "\n")
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }
}

// 設計判断: DEC-MTG-067
/// アクションアイテムを選んでリマインダーに登録するシート
struct ReminderExportSheet: View {
    let meeting: Meeting
    @ObservedObject var recorder: MeetingRecorder
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ActionItem] = []
    @State private var selected: Set<UUID> = []
    @State private var listID = ""
    @State private var lists: [(id: String, title: String)] = []
    @State private var message: String?
    @State private var denied = false
    @State private var working = false
    @State private var done = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("リマインダーに登録").font(.headline)
            Text("登録するアクションアイテムを選んでください。期限の日付が分かるものは期限付きで登録します。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if items.isEmpty {
                Text("この議事録にはアクションアイテムがありません。").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { item in
                            Toggle(isOn: binding(for: item)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.task)
                                    HStack(spacing: 10) {
                                        if let owner = item.owner { Label(owner, systemImage: "person") }
                                        if let due = item.dueDisplay { Label(due, systemImage: "calendar") }
                                        if item.reminderID != nil {
                                            Label("登録済み", systemImage: "checkmark.circle").foregroundStyle(.green)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // ScrollView には決まった高さがないので、件数から決める（多いときはスクロール）
                .frame(height: min(260, CGFloat(items.count) * 42))
                .scrollBounceBehavior(.basedOnSize)
            }
            if !lists.isEmpty {
                Picker("登録先", selection: $listID) {
                    ForEach(lists, id: \.id) { Text($0.title).tag($0.id) }
                }
                .frame(maxWidth: 280)
            } else if !denied {
                Text("初めて登録するときは、リマインダーへのアクセスの許可を求めます。登録先は既定のリストです。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message {
                HStack {
                    Text(message).font(.caption).foregroundStyle(denied ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if denied {
                        Button("システム設定を開く") { ReminderExporter.openPrivacySettings() }.controlSize(.small)
                    }
                }
            }
            HStack {
                Spacer()
                if done {
                    Button("閉じる") { dismiss() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("キャンセル") { dismiss() }
                    Button("\(selected.count) 件を登録") { Task { await register() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selected.isEmpty || working)
                }
            }
        }
        .padding()
        .frame(width: 440)
        .onAppear { load() }
    }

    private func binding(for item: ActionItem) -> Binding<Bool> {
        Binding(get: { selected.contains(item.id) },
                set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } })
    }

    private func load() {
        items = meeting.resolvedActionItems
        // 初期値: まだ登録していない、自分の担当か担当が決まっていないもの
        let me = meeting.displayName(for: "me")
        selected = Set(items.filter { $0.reminderID == nil && ($0.owner == nil || $0.owner == me || $0.owner == "自分") }.map(\.id))
        reloadLists()
    }

    private func reloadLists() {
        lists = ReminderExporter.lists().map { ($0.calendarIdentifier, $0.title) }
        if listID.isEmpty || !lists.contains(where: { $0.id == listID }) {
            listID = ReminderExporter.defaultList?.calendarIdentifier ?? lists.first?.id ?? ""
        }
    }

    private func register() async {
        working = true
        defer { working = false }
        do {
            guard try await ReminderExporter.ensureAccess() else {
                denied = true
                message = "リマインダーへのアクセスが許可されていません。システム設定 → プライバシーとセキュリティ → リマインダー で Hanasu をオンにしてください。"
                return
            }
            let list = ReminderExporter.list(withID: listID)
            let chosen = items.filter { selected.contains($0.id) }
            let ids = try ReminderExporter.add(chosen, meeting: meeting, to: list)
            recorder.markRemindersAdded(meeting, items: items, reminderIDs: ids)
            for index in items.indices { if let id = ids[items[index].id] { items[index].reminderID = id } }
            selected = []
            reloadLists()
            let listName = (list ?? ReminderExporter.defaultList)?.title ?? "既定のリスト"
            message = "\(ids.count) 件をリマインダー「\(listName)」に登録しました。"
            done = true
        } catch {
            message = "登録できませんでした: \(error.localizedDescription)"
        }
    }
}

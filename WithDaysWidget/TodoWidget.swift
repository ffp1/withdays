import AppIntents
import EventKit
import SwiftUI
import WidgetKit

/// The ToDo category chosen in Settings (メイン by default), with check buttons that work without opening the app.
struct TodoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodoWidget", provider: TodoProvider()) { entry in
            TodoWidgetView(entry: entry)
        }
        .configurationDisplayName("ToDo")
        .description("設定で選んだカテゴリのToDoを表示します。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: Intent

/// Marks a reminder done from the widget.
struct CompleteTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "ToDoを完了にする"

    @Parameter(title: "ID")
    var reminderID: String

    init() {}

    init(reminderID: String) {
        self.reminderID = reminderID
    }

    func perform() async throws -> some IntentResult {
        let store = EKEventStore()
        if let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder {
            reminder.isCompleted = true
            try store.save(reminder, commit: true)
        }
        return .result()
    }
}

// MARK: Data

struct TodoEntry: TimelineEntry {
    let date: Date
    let title: String
    let color: Color
    let rows: [TodoRow]
    let count: Int
    let hasAccess: Bool
}

struct TodoProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry {
        TodoEntry(date: .now, title: "メイン", color: .brand, rows: [], count: 0, hasAccess: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        Task { completion(await TodoLoader.load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        // The app reloads the widget on every change; the hourly refresh catches edits made elsewhere.
        Task {
            let entry = await TodoLoader.load()
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
        }
    }
}

enum TodoLoader {
    static func load() async -> TodoEntry {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            return TodoEntry(date: .now, title: "ToDo", color: .brand, rows: [], count: 0, hasAccess: false)
        }
        let store = EKEventStore()
        let lists = store.calendars(for: .reminder)
        let chosen = AppGroup.defaults.string(forKey: SettingsKey.todoWidgetList) ?? ""
        guard let list = lists.first(where: { $0.calendarIdentifier == chosen })
            ?? lists.first(where: { $0.title == "メイン" })
            ?? lists.first
        else {
            return TodoEntry(date: .now, title: "ToDo", color: .brand, rows: [], count: 0, hasAccess: true)
        }

        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
        let items = reminders.map {
            TodoItem(
                id: $0.calendarItemIdentifier,
                title: $0.title ?? "",
                notes: $0.notes ?? "",
                isCompleted: false,
                creationDate: $0.creationDate ?? .distantPast,
                completionDate: nil
            )
        }
        let rows = TodoTree.rows(items, listID: list.calendarIdentifier, meta: TodoMeta.load())
        return TodoEntry(date: .now, title: list.title, color: Color(cgColor: list.cgColor), rows: rows, count: items.count, hasAccess: true)
    }
}

// MARK: Views

struct TodoWidgetView: View {
    let entry: TodoEntry

    @Environment(\.widgetFamily) private var family

    private var maxRows: Int { family == .systemLarge ? 11 : 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(entry.color)
                Text(entry.count > 99 ? "99+" : "\(entry.count)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(entry.color))
                Spacer()
            }

            if !entry.hasAccess {
                Text("WithDays を開いて、リマインダーへのアクセスを許可してください。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(entry.rows.prefix(maxRows)) { row in
                    HStack(spacing: 8) {
                        Button(intent: CompleteTodoIntent(reminderID: row.id)) {
                            Image(systemName: "circle")
                                .font(.system(size: 17))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        Text(row.item.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if row.childCount > 0 {
                            Text("\(row.childCount)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, CGFloat(row.depth) * 22)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "\(DeepLink.scheme)://todo"))
        .themedWidget()
    }
}

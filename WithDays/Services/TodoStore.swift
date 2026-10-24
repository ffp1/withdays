import EventKit
import SwiftUI
import WidgetKit

/// ToDo backed by Apple's Reminders: categories are reminder lists, items are reminders.
/// Subtasks and manual order live in `TodoMeta`, since EventKit has no API for them.
@MainActor
@Observable
final class TodoStore {
    @ObservationIgnored let eventStore = EKEventStore()

    static let defaultListNames = ["メイン", "やること", "買い物"]

    private(set) var status = EKEventStore.authorizationStatus(for: .reminder)
    private(set) var lists: [EKCalendar] = []
    /// Incomplete and completed items per list ID.
    private(set) var open: [String: [TodoItem]] = [:]
    private(set) var done: [String: [TodoItem]] = [:]
    private(set) var meta = TodoMeta.load()

    var hiddenListIDs: Set<String> {
        didSet {
            AppGroup.defaults.set(Array(hiddenListIDs), forKey: SettingsKey.hiddenTodoLists)
            if !visibleLists.contains(where: { $0.calendarIdentifier == selectedListID }) {
                selectedListID = visibleLists.first?.calendarIdentifier ?? ""
            }
        }
    }

    var widgetListID: String {
        didSet {
            AppGroup.defaults.set(widgetListID, forKey: SettingsKey.todoWidgetList)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    var selectedListID: String {
        didSet { UserDefaults.standard.set(selectedListID, forKey: SettingsKey.selectedTodoList) }
    }

    @ObservationIgnored private var reminders: [String: EKReminder] = [:]
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init() {
        hiddenListIDs = Set(AppGroup.defaults.stringArray(forKey: SettingsKey.hiddenTodoLists) ?? [])
        widgetListID = AppGroup.defaults.string(forKey: SettingsKey.todoWidgetList) ?? ""
        selectedListID = UserDefaults.standard.string(forKey: SettingsKey.selectedTodoList) ?? ""
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        if access == .granted { reload() }
    }

    // MARK: Access

    var access: CalendarAccess {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    func requestAccess() async {
        _ = try? await eventStore.requestFullAccessToReminders()
        status = EKEventStore.authorizationStatus(for: .reminder)
        if access == .granted { reload() }
    }

    // MARK: Lists

    /// The three default lists first, then the rest by name; hidden ones left out.
    var visibleLists: [EKCalendar] {
        sortedLists.filter { !hiddenListIDs.contains($0.calendarIdentifier) }
    }

    var sortedLists: [EKCalendar] {
        lists.sorted { a, b in
            let ia = Self.defaultListNames.firstIndex(of: a.title) ?? Int.max
            let ib = Self.defaultListNames.firstIndex(of: b.title) ?? Int.max
            if ia != ib { return ia < ib }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    var selectedList: EKCalendar? {
        visibleLists.first { $0.calendarIdentifier == selectedListID } ?? visibleLists.first
    }

    func list(id: String) -> EKCalendar? {
        lists.first { $0.calendarIdentifier == id }
    }

    func createList(title: String, color: UIColor) throws -> EKCalendar {
        let list = EKCalendar(for: .reminder, eventStore: eventStore)
        list.title = title
        list.cgColor = color.cgColor
        guard let source = eventStore.defaultCalendarForNewReminders()?.source
            ?? eventStore.sources.first(where: { $0.sourceType == .calDAV })
            ?? eventStore.sources.first(where: { $0.sourceType == .local })
        else { throw AppError(message: "リストを追加できるアカウントが見つかりません。") }
        list.source = source
        try eventStore.saveCalendar(list, commit: true)
        reload()
        return list
    }

    func updateList(_ list: EKCalendar, title: String, color: UIColor) throws {
        list.title = title
        list.cgColor = color.cgColor
        try eventStore.saveCalendar(list, commit: true)
        reload()
    }

    func deleteList(_ list: EKCalendar) throws {
        try eventStore.removeCalendar(list, commit: true)
        hiddenListIDs.remove(list.calendarIdentifier)
        reload()
    }

    /// On first access, create メイン / やること / 買い物 if missing. Once only, so deleted ones stay deleted.
    private func ensureDefaultLists() {
        guard !UserDefaults.standard.bool(forKey: SettingsKey.createdDefaultTodoLists) else { return }
        UserDefaults.standard.set(true, forKey: SettingsKey.createdDefaultTodoLists)
        let existing = Set(eventStore.calendars(for: .reminder).map(\.title))
        for (index, name) in Self.defaultListNames.enumerated() where !existing.contains(name) {
            let list = EKCalendar(for: .reminder, eventStore: eventStore)
            list.title = name
            list.cgColor = CalendarPalette.colors[[6, 3, 1][index]].cgColor
            list.source = eventStore.defaultCalendarForNewReminders()?.source
            if list.source != nil { try? eventStore.saveCalendar(list, commit: true) }
        }
    }

    // MARK: Loading

    func reload() {
        guard access == .granted else { return }
        ensureDefaultLists()
        lists = eventStore.calendars(for: .reminder)
        if widgetListID.isEmpty, let main = lists.first(where: { $0.title == Self.defaultListNames[0] }) {
            widgetListID = main.calendarIdentifier
        }
        if selectedListID.isEmpty || list(id: selectedListID) == nil {
            selectedListID = visibleLists.first?.calendarIdentifier ?? ""
        }
        loadTask?.cancel()
        let calendars = lists
        loadTask = Task {
            guard !calendars.isEmpty else { return }
            let openPredicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
            let start = CalendarMath.calendar.date(byAdding: .month, value: -6, to: .now)
            let donePredicate = eventStore.predicateForCompletedReminders(withCompletionDateStarting: start, ending: nil, calendars: calendars)
            let openItems = await fetch(openPredicate)
            let doneItems = await fetch(donePredicate)
            guard !Task.isCancelled else { return }
            apply(open: openItems, done: doneItems)
        }
    }

    private func fetch(_ predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
    }

    private func apply(open openItems: [EKReminder], done doneItems: [EKReminder]) {
        var map: [String: EKReminder] = [:]
        func convert(_ reminder: EKReminder) -> TodoItem {
            map[reminder.calendarItemIdentifier] = reminder
            return TodoItem(
                id: reminder.calendarItemIdentifier,
                title: reminder.title ?? "",
                notes: reminder.notes ?? "",
                isCompleted: reminder.isCompleted,
                creationDate: reminder.creationDate ?? .distantPast,
                completionDate: reminder.completionDate
            )
        }
        open = Dictionary(grouping: openItems) { $0.calendar.calendarIdentifier }.mapValues { $0.map(convert) }
        done = Dictionary(grouping: doneItems) { $0.calendar.calendarIdentifier }
            .mapValues { $0.map(convert).sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) } }
        reminders = map
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Items

    func rows(for listID: String) -> [TodoRow] {
        TodoTree.rows(open[listID] ?? [], listID: listID, meta: meta)
    }

    func count(for listID: String) -> Int {
        open[listID]?.count ?? 0
    }

    /// Saves a new reminder at the end of the list (or after its parent's other subtasks).
    @discardableResult
    func add(title: String, notes: String, to listID: String, parent: String? = nil) throws -> String {
        guard let list = list(id: listID) else { throw AppError(message: "リストが見つかりません。") }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = list
        reminder.title = title
        reminder.notes = notes.isEmpty ? nil : notes
        try eventStore.save(reminder, commit: true)
        let id = reminder.calendarItemIdentifier
        var order = currentOrder(listID)
        if let parent, let parentIndex = order.firstIndex(of: parent) {
            let lastChild = order.lastIndex { meta.parents[$0] == parent } ?? parentIndex
            order.insert(id, at: lastChild + 1)
            meta.parents[id] = parent
        } else {
            order.append(id)
        }
        meta.order[listID] = order
        saveMeta()
        reload()
        return id
    }

    func update(_ id: String, title: String, notes: String) throws {
        guard let reminder = reminders[id] else { return }
        guard reminder.title != title || (reminder.notes ?? "") != notes else { return }
        reminder.title = title
        reminder.notes = notes.isEmpty ? nil : notes
        try eventStore.save(reminder, commit: true)
        reload()
    }

    func setCompleted(_ id: String, _ completed: Bool) throws {
        guard let reminder = reminders[id] else { return }
        reminder.isCompleted = completed
        try eventStore.save(reminder, commit: true)
        reload()
    }

    /// Deletes the item and its subtasks.
    func delete(_ id: String) throws {
        let ids = [id] + meta.parents.filter { $0.value == id }.map(\.key)
        for itemID in ids {
            if let reminder = reminders[itemID] { try eventStore.remove(reminder, commit: false) }
            meta.parents[itemID] = nil
        }
        try eventStore.commit()
        saveMeta()
        reload()
    }

    /// Makes the item a subtask of the top-level row directly above it.
    func indent(_ id: String, in listID: String) {
        let rows = TodoTree.rows(open[listID] ?? [], listID: listID, meta: meta, includeCollapsed: true)
        guard let index = rows.firstIndex(where: { $0.id == id }), index > 0, rows[index].depth == 0,
              rows[index].childCount == 0
        else { return }
        let above = rows[index - 1]
        let parent = above.depth == 0 ? above.id : (meta.parents[above.id] ?? above.id)
        guard parent != id else { return }
        meta.parents[id] = parent
        meta.order[listID] = rows.map(\.id)
        meta.collapsed.remove(parent)
        saveMeta()
    }

    func outdent(_ id: String, in listID: String) {
        guard meta.parents[id] != nil else { return }
        meta.parents[id] = nil
        saveMeta()
    }

    func toggleCollapsed(_ id: String) {
        if meta.collapsed.contains(id) { meta.collapsed.remove(id) } else { meta.collapsed.insert(id) }
        saveMeta()
    }

    /// The saved order, with items it doesn't know yet appended.
    private func currentOrder(_ listID: String) -> [String] {
        TodoTree.rows(open[listID] ?? [], listID: listID, meta: meta, includeCollapsed: true).map(\.id)
    }

    private func saveMeta() {
        meta.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

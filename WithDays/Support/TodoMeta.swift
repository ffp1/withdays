import Foundation

/// What Reminders can't store through EventKit: subtask parents, manual order and folded parents.
/// Kept in the App Group so the widget shows the same tree.
struct TodoMeta: Codable, Equatable {
    /// Parent reminder ID for each subtask.
    var parents: [String: String] = [:]
    /// Manual order of reminder IDs per list.
    var order: [String: [String]] = [:]
    var collapsed: Set<String> = []

    static func load() -> TodoMeta {
        guard let data = AppGroup.defaults.data(forKey: SettingsKey.todoMeta),
              let meta = try? JSONDecoder().decode(TodoMeta.self, from: data)
        else { return TodoMeta() }
        return meta
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppGroup.defaults.set(data, forKey: SettingsKey.todoMeta)
        }
    }
}

/// A reminder as the list shows it.
struct TodoItem: Identifiable, Equatable {
    let id: String
    var title: String
    var notes: String
    var isCompleted: Bool
    var creationDate: Date
    var completionDate: Date?
}

/// One visible row: the item, its depth and how many subtasks it has.
struct TodoRow: Identifiable, Equatable {
    let item: TodoItem
    let depth: Int
    let childCount: Int

    var id: String { item.id }
}

enum TodoTree {
    /// Orders items by the saved order (new ones last, oldest first), then nests subtasks under their parent.
    /// A subtask whose parent isn't in `items` (e.g. the parent is done) shows at the top level.
    static func rows(_ items: [TodoItem], listID: String, meta: TodoMeta, includeCollapsed: Bool = false) -> [TodoRow] {
        let order = meta.order[listID] ?? []
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let sorted = items.sorted { a, b in
            switch (rank[a.id], rank[b.id]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.creationDate < b.creationDate
            }
        }
        let ids = Set(items.map(\.id))
        let children = Dictionary(grouping: sorted.filter { meta.parents[$0.id].map(ids.contains) == true }) { meta.parents[$0.id] ?? "" }
        var rows: [TodoRow] = []
        for item in sorted where meta.parents[item.id].map(ids.contains) != true {
            let kids = children[item.id] ?? []
            rows.append(TodoRow(item: item, depth: 0, childCount: kids.count))
            if includeCollapsed || !meta.collapsed.contains(item.id) {
                rows += kids.map { TodoRow(item: $0, depth: 1, childCount: 0) }
            }
        }
        return rows
    }
}

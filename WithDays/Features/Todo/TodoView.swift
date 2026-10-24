import EventKit
import SwiftUI

/// ToDo mode: category bar, then the list. Tap to edit in place; tap empty space or ＋ to add.
struct TodoView: View {
    @Environment(TodoStore.self) private var todos
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch todos.access {
            case .granted:
                TodoContent()
            case .undetermined:
                // Asks on its own, but keeps a button in case the system prompt doesn't come up.
                ContentUnavailableView {
                    Label("リマインダーへのアクセス", systemImage: "checklist")
                } description: {
                    if let error = todos.accessError { Text(error) }
                } actions: {
                    Button("アクセスを許可") { Task { await todos.requestAccess() } }
                        .buttonStyle(.glassProminent)
                }
                .task { await todos.requestAccess() }
            case .denied:
                ContentUnavailableView {
                    Label("リマインダーへのアクセスが必要です", systemImage: "checklist")
                } actions: {
                    Button("設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { todos.refreshStatus() }
        }
    }
}

enum CategorySheet: Identifiable {
    case new
    case edit(EKCalendar)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let list): list.calendarIdentifier
        }
    }
}

private enum TodoField: Hashable {
    case title, notes
}

private struct TodoContent: View {
    @Environment(TodoStore.self) private var todos

    /// The row being edited: an item ID, or `newID` for an item not saved yet.
    @State private var editingID: String?
    @State private var draftTitle = ""
    @State private var draftNotes = ""
    /// Subtask parent for a new item indented before it was saved.
    @State private var draftParent: String?
    @State private var showDone = false
    /// Checked items wait 3 seconds before moving to 実行済み; checking again in that time cancels.
    @State private var pendingDone: [String: Task<Void, Never>] = [:]
    /// Direction of the last category change, for the slide.
    @State private var forward = true
    @State private var categorySheet: CategorySheet?
    @State private var errorMessage: String?
    @FocusState private var focus: TodoField?

    private static let newID = "__new__"

    private var listID: String { todos.selectedList?.calendarIdentifier ?? "" }

    private var listColor: Color {
        todos.selectedList.map { Color(cgColor: $0.cgColor) } ?? .brand
    }

    var body: some View {
        let doneItems = todos.done[listID] ?? []
        VStack(spacing: 0) {
            CategoryBar(
                onSelect: selectList,
                onAdd: { categorySheet = .new },
                onEdit: { categorySheet = .edit($0) }
            )
            ZStack {
                list(doneItems: doneItems)
                    .id(listID)
                    .transition(.push(from: forward ? .trailing : .leading))
            }
            .clipped()
            .animation(.snappy(duration: 0.3), value: listID)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 12) {
                // 実行済み stays at the bottom while the ToDo list is open.
                if !showDone, !doneItems.isEmpty {
                    sectionHeader("実行済み", count: doneItems.count, open: false) {
                        withAnimation(.snappy) {
                            commitEditing()
                            showDone = true
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .glassEffect(.regular, in: .capsule)
                } else {
                    Spacer()
                }
                Button(action: startNew) {
                    Image(systemName: "plus")
                        .font(.system(size: 26.4, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
            }
            .padding(20)
        }
        .onChange(of: focus) { _, new in
            if new == nil { commitEditing() }
        }
        .onChange(of: listID) { _, _ in
            cancelEditing()
            showDone = false
        }
        .sheet(item: $categorySheet) { sheet in
            CategoryEditorView(sheet: sheet)
        }
        .sensoryFeedback(.success, trigger: doneItems.count) { old, new in new > old }
        .errorAlert($errorMessage)
    }

    private func list(doneItems: [TodoItem]) -> some View {
        List {
            if showDone {
                sectionHeader("ToDo", count: todos.count(for: listID), open: false) {
                    withAnimation(.snappy) { showDone = false }
                }
                .listRowSeparator(.hidden, edges: .top)
                sectionHeader("実行済み", count: doneItems.count, open: true) {
                    withAnimation(.snappy) { showDone = false }
                }
                ForEach(doneItems) { item in
                    TodoItemRow(
                        item: item, depth: 0, childCount: 0, collapsed: false, color: listColor,
                        checked: true, isEditing: false,
                        draftTitle: $draftTitle, draftNotes: $draftNotes, focus: $focus,
                        onToggle: { toggle(item) }, onFold: {}, onTap: {}, onIndent: {}, onOutdent: {}
                    )
                    .swipeActions(edge: .trailing) { deleteButton(item.id) }
                }
            } else {
                ForEach(todos.rows(for: listID)) { row in
                    let editing = editingID == row.id
                    TodoItemRow(
                        item: row.item,
                        depth: row.depth,
                        childCount: row.childCount,
                        collapsed: todos.meta.collapsed.contains(row.id),
                        color: listColor,
                        checked: pendingDone[row.id] != nil,
                        isEditing: editing,
                        draftTitle: $draftTitle,
                        draftNotes: $draftNotes,
                        focus: $focus,
                        onToggle: { toggle(row.item) },
                        onFold: { withAnimation(.snappy) { todos.toggleCollapsed(row.id) } },
                        onTap: { startEditing(row.item) },
                        onIndent: indentEditing,
                        onOutdent: outdentEditing
                    )
                    .listRowSeparator(editing ? .hidden : .automatic)
                    .swipeActions(edge: .trailing) {
                        if !editing { deleteButton(row.id) }
                    }
                }
                if editingID == Self.newID {
                    TodoItemRow(
                        item: TodoItem(id: Self.newID, title: "", notes: "", isCompleted: false, creationDate: .now),
                        depth: draftParent == nil ? 0 : 1, childCount: 0, collapsed: false, color: listColor,
                        checked: false, isEditing: true,
                        draftTitle: $draftTitle, draftNotes: $draftNotes, focus: $focus,
                        onToggle: {}, onFold: {}, onTap: {}, onIndent: indentEditing, onOutdent: outdentEditing
                    )
                    .listRowSeparator(.hidden)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // Empty space: tap adds an item (or only ends editing); swipe changes the category.
            Color.clear
                .frame(height: 320)
                .contentShape(Rectangle())
                .onTapGesture(perform: tapEmptySpace)
                .gesture(categorySwipe)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .animation(.snappy, value: todos.rows(for: listID))
    }

    private func sectionHeader(_ title: String, count: Int, open: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                Text("\(count)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func deleteButton(_ id: String) -> some View {
        Button(role: .destructive) {
            run { try todos.delete(id) }
        } label: {
            Image(systemName: "trash")
        }
        .tint(.red)
    }

    private var categorySwipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 1.5, abs(value.translation.width) > 50 else { return }
            let lists = todos.visibleLists
            guard let index = lists.firstIndex(where: { $0.calendarIdentifier == listID }) else { return }
            let next = index + (value.translation.width < 0 ? 1 : -1)
            guard lists.indices.contains(next) else { return }
            selectList(lists[next])
        }
    }

    private func selectList(_ list: EKCalendar) {
        let lists = todos.visibleLists
        let from = lists.firstIndex { $0.calendarIdentifier == listID } ?? 0
        let to = lists.firstIndex { $0.calendarIdentifier == list.calendarIdentifier } ?? 0
        forward = to >= from
        withAnimation(.snappy(duration: 0.3)) { todos.selectedListID = list.calendarIdentifier }
    }

    // MARK: Editing

    private func startEditing(_ item: TodoItem) {
        commitEditing()
        draftTitle = item.title
        draftNotes = item.notes
        draftParent = nil
        withAnimation(.snappy(duration: 0.3)) { editingID = item.id }
        focus = .title
    }

    private func startNew() {
        commitEditing()
        draftTitle = ""
        draftNotes = ""
        draftParent = nil
        withAnimation(.snappy(duration: 0.3)) {
            showDone = false
            editingID = Self.newID
        }
        focus = .title
    }

    private func tapEmptySpace() {
        if editingID != nil {
            focus = nil
            commitEditing()
        } else {
            startNew()
        }
    }

    /// Saves the open row: a new item only if it has a title; an existing one only if it changed.
    private func commitEditing() {
        guard let id = editingID else { return }
        withAnimation(.snappy(duration: 0.3)) { editingID = nil }
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if id == Self.newID {
            guard !title.isEmpty else { return }
            run { try todos.add(title: title, notes: notes, to: listID, parent: draftParent) }
        } else if !title.isEmpty {
            run { try todos.update(id, title: title, notes: notes) }
        }
    }

    private func cancelEditing() {
        editingID = nil
        focus = nil
    }

    private func indentEditing() {
        guard let id = editingID else { return }
        if id == Self.newID {
            // The new item will become a subtask of the last top-level item.
            withAnimation(.snappy) { draftParent = todos.rows(for: listID).last { $0.depth == 0 }?.id }
        } else {
            withAnimation(.snappy) { todos.indent(id, in: listID) }
        }
    }

    private func outdentEditing() {
        guard let id = editingID else { return }
        if id == Self.newID {
            withAnimation(.snappy) { draftParent = nil }
        } else {
            withAnimation(.snappy) { todos.outdent(id, in: listID) }
        }
    }

    /// Done items go back immediately; open items move to 実行済み 3 seconds after being checked.
    private func toggle(_ item: TodoItem) {
        if item.isCompleted {
            run { try todos.setCompleted(item.id, false) }
            return
        }
        if let task = pendingDone.removeValue(forKey: item.id) {
            task.cancel()
            return
        }
        pendingDone[item.id] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            pendingDone[item.id] = nil
            withAnimation(.snappy) { run { try todos.setCompleted(item.id, true) } }
        }
    }

    private func run(_ work: () throws -> Void) {
        do { try work() } catch { errorMessage = error.localizedDescription }
    }
}

/// One row that turns into its own editor in place: the title becomes editable where it sits,
/// the notes field opens under it and the row lifts with a shadow.
private struct TodoItemRow: View {
    let item: TodoItem
    let depth: Int
    let childCount: Int
    let collapsed: Bool
    let color: Color
    /// Completed, or checked and waiting to move.
    let checked: Bool
    let isEditing: Bool
    @Binding var draftTitle: String
    @Binding var draftNotes: String
    var focus: FocusState<TodoField?>.Binding
    var onToggle: () -> Void
    var onFold: () -> Void
    var onTap: () -> Void
    var onIndent: () -> Void
    var onOutdent: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(checked ? color : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(isEditing)

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("タイトル", text: $draftTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .focused(focus, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focus.wrappedValue = .notes }
                    TextField("メモ", text: $draftNotes, axis: .vertical)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .focused(focus, equals: .notes)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(checked ? .secondary : .primary)
                        .strikethrough(item.isCompleted)
                    if !item.notes.isEmpty {
                        Text(item.notes)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if childCount > 0, !isEditing {
                Button(action: onFold) {
                    HStack(spacing: 4) {
                        Text("\(childCount)")
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .rotationEffect(.degrees(collapsed ? 0 : 90))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, CGFloat(depth) * 28)
        .padding(.vertical, isEditing ? 8 : 4)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(isEditing ? 0.14 : 0), radius: isEditing ? 10 : 0, y: isEditing ? 4 : 0)
                .padding(.horizontal, -10)
                .opacity(isEditing ? 1 : 0)
        }
        .scaleEffect(isEditing ? 1.01 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { onTap() } }
        // Swipe right while editing to make it a subtask of the item above; left to undo that.
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                if value.translation.width > 50 { onIndent() } else if value.translation.width < -50 { onOutdent() }
            },
            including: isEditing ? .all : .subviews
        )
    }
}

/// Categories side by side with their open counts; ＋ at the end adds one, tapping the current one edits it.
private struct CategoryBar: View {
    var onSelect: (EKCalendar) -> Void
    var onAdd: () -> Void
    var onEdit: (EKCalendar) -> Void

    @Environment(TodoStore.self) private var todos

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ForEach(todos.visibleLists, id: \.calendarIdentifier) { list in
                    let selected = list.calendarIdentifier == todos.selectedList?.calendarIdentifier
                    let color = Color(cgColor: list.cgColor)
                    Button {
                        if selected {
                            onEdit(list)
                        } else {
                            onSelect(list)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(list.title)
                                .font(.system(size: 15, weight: selected ? .bold : .medium))
                                .foregroundStyle(selected ? color : Color.secondary)
                            CountBadge(count: todos.count(for: list.calendarIdentifier), color: selected ? color : Color(.systemGray3))
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }
}

struct CountBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(color))
    }
}

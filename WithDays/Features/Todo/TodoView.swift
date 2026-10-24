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
    @State private var categorySheet: CategorySheet?
    @State private var errorMessage: String?
    @FocusState private var focus: TodoField?

    private static let newID = "__new__"

    private var listID: String { todos.selectedList?.calendarIdentifier ?? "" }

    private var listColor: Color {
        todos.selectedList.map { Color(cgColor: $0.cgColor) } ?? .brand
    }

    var body: some View {
        VStack(spacing: 0) {
            CategoryBar(onAdd: { categorySheet = .new }, onEdit: { categorySheet = .edit($0) })
            List {
                if showDone {
                    sectionHeader("ToDo", count: todos.count(for: listID)) {
                        withAnimation(.snappy) { showDone = false }
                    }
                } else {
                    ForEach(todos.rows(for: listID)) { row in
                        rowView(row)
                    }
                    if editingID == Self.newID {
                        editor(depth: draftParent == nil ? 0 : 1)
                            .listRowSeparator(.hidden)
                            .listRowBackground(liftedBackground)
                    }
                }

                let doneItems = todos.done[listID] ?? []
                if !doneItems.isEmpty {
                    sectionHeader("実行済み", count: doneItems.count, open: showDone) {
                        withAnimation(.snappy) {
                            commitEditing()
                            showDone.toggle()
                        }
                    }
                    if showDone {
                        ForEach(doneItems) { item in
                            TodoRowLabel(item: item, depth: 0, childCount: 0, collapsed: false, color: listColor,
                                         onToggle: { toggle(item) }, onFold: {})
                                .swipeActions(edge: .trailing) { deleteButton(item.id) }
                        }
                    }
                }

                // Empty space: adds an item, or just ends editing if one is open.
                Color.clear
                    .frame(height: 240)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: tapEmptySpace)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .animation(.snappy, value: todos.rows(for: listID))
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: startNew) {
                Image(systemName: "plus")
                    .font(.system(size: 26.4, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
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
        .sensoryFeedback(.success, trigger: todos.done[listID]?.count ?? 0) { old, new in new > old }
        .errorAlert($errorMessage)
    }

    // MARK: Rows

    @ViewBuilder
    private func rowView(_ row: TodoRow) -> some View {
        if editingID == row.id {
            editor(depth: row.depth)
                .listRowSeparator(.hidden)
                .listRowBackground(liftedBackground)
        } else {
            TodoRowLabel(
                item: row.item,
                depth: row.depth,
                childCount: row.childCount,
                collapsed: todos.meta.collapsed.contains(row.id),
                color: listColor,
                onToggle: { toggle(row.item) },
                onFold: { withAnimation(.snappy) { todos.toggleCollapsed(row.id) } }
            )
            .contentShape(Rectangle())
            .onTapGesture { startEditing(row.item) }
            .swipeActions(edge: .trailing) { deleteButton(row.id) }
        }
    }

    /// The row being edited floats slightly above the list.
    private var liftedBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
    }

    private func editor(depth: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 4) {
                TextField("タイトル", text: $draftTitle)
                    .font(.system(size: 16, weight: .bold))
                    .focused($focus, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focus = .notes }
                TextField("メモ", text: $draftNotes, axis: .vertical)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .focused($focus, equals: .notes)
            }
        }
        .padding(.leading, CGFloat(depth) * 28)
        .padding(.vertical, 6)
        .animation(.snappy, value: depth)
        // Swipe right while editing to make it a subtask of the item above; left to undo that.
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                if value.translation.width > 50 { indentEditing() } else if value.translation.width < -50 { outdentEditing() }
            }
        )
    }

    private func sectionHeader(_ title: String, count: Int, open: Bool = false, action: @escaping () -> Void) -> some View {
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

    // MARK: Editing

    private func startEditing(_ item: TodoItem) {
        commitEditing()
        editingID = item.id
        draftTitle = item.title
        draftNotes = item.notes
        draftParent = nil
        focus = .title
    }

    private func startNew() {
        commitEditing()
        withAnimation(.snappy) { showDone = false }
        editingID = Self.newID
        draftTitle = ""
        draftNotes = ""
        draftParent = nil
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
        editingID = nil
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
            draftParent = todos.rows(for: listID).last { $0.depth == 0 }?.id
        } else {
            withAnimation(.snappy) { todos.indent(id, in: listID) }
        }
    }

    private func outdentEditing() {
        guard let id = editingID else { return }
        if id == Self.newID {
            draftParent = nil
        } else {
            withAnimation(.snappy) { todos.outdent(id, in: listID) }
        }
    }

    private func toggle(_ item: TodoItem) {
        run { try todos.setCompleted(item.id, !item.isCompleted) }
    }

    private func run(_ work: () throws -> Void) {
        do { try work() } catch { errorMessage = error.localizedDescription }
    }
}

/// A list row: check button, title and notes, and for parents the subtask count with a fold chevron.
private struct TodoRowLabel: View {
    let item: TodoItem
    let depth: Int
    let childCount: Int
    let collapsed: Bool
    let color: Color
    var onToggle: () -> Void
    var onFold: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(item.isCompleted ? color : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .strikethrough(item.isCompleted)
                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if childCount > 0 {
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
        .padding(.vertical, 4)
    }
}

/// Categories side by side with their open counts; ＋ at the end adds one, tapping the current one edits it.
private struct CategoryBar: View {
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
                            withAnimation(.snappy) { todos.selectedListID = list.calendarIdentifier }
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

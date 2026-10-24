import EventKit
import SwiftUI

/// Adds or edits a ToDo category (a Reminders list): name and color, plus delete when editing.
struct CategoryEditorView: View {
    let sheet: CategorySheet

    @Environment(TodoStore.self) private var todos
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var color: ColorChoice
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    init(sheet: CategorySheet) {
        self.sheet = sheet
        switch sheet {
        case .new:
            _title = State(initialValue: "")
            _color = State(initialValue: ColorChoice())
        case .edit(let list):
            _title = State(initialValue: list.title)
            _color = State(initialValue: ColorChoice(color: UIColor(cgColor: list.cgColor)))
        }
    }

    private var editingList: EKCalendar? {
        if case .edit(let list) = sheet { return list }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("カテゴリ名", text: $title)
                        .font(.system(size: 17 * 1.2, weight: .bold))
                        .focused($titleFocused)
                }
                Section("色") {
                    ColorGrid(choice: $color)
                }
                if editingList != nil {
                    Section {
                        Button("カテゴリを削除", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(editingList == nil ? "カテゴリを追加" : "カテゴリを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .buttonStyle(.glassProminent)
                        .tint(.brand)
                }
            }
            .confirmationDialog("「\(editingList?.title ?? "")」とその中のToDoを削除します", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive, action: delete)
            }
            .errorAlert($errorMessage)
        }
        .task {
            if editingList == nil {
                try? await Task.sleep(for: .milliseconds(400))
                titleFocused = true
            }
        }
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            if let list = editingList {
                try todos.updateList(list, title: name, color: color.uiColor)
            } else {
                let list = try todos.createList(title: name, color: color.uiColor)
                todos.selectedListID = list.calendarIdentifier
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        guard let list = editingList else { return }
        do {
            try todos.deleteList(list)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

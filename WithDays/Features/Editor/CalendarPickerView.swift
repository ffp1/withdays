import EventKit
import SwiftUI

/// Every writable calendar; picking one (even the current one) goes straight back.
/// Swipe right to edit, left to delete.
struct CalendarPickerView: View {
    let selectedID: String?
    var onPick: (String) -> Void

    @Environment(CalendarStore.self) private var store
    @State private var pendingDelete: EKCalendar?
    @State private var editing: EKCalendar?
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(store.grouped(store.writableCalendars)) { group in
                Section(group.source) {
                    ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                        Button {
                            onPick(calendar.calendarIdentifier)
                        } label: {
                            HStack(spacing: 10) {
                                CalendarDot(color: Color(cgColor: calendar.cgColor))
                                Text(calendar.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if calendar.calendarIdentifier == selectedID {
                                    CheckMark()
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .calendarEditSwipe(calendar, editing: $editing)
                        .swipeActions(edge: .trailing) {
                            if store.canDelete(calendar) {
                                Button(role: .destructive) { pendingDelete = calendar } label: {
                                    Image(systemName: "trash")
                                }
                                .tint(.red)
                            }
                        }
                    }
                }
            }
            Section {
                NavigationLink(value: EditorPath.newCalendar) {
                    Label("カレンダーを追加", systemImage: "plus")
                        .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("カレンダー")
        .navigationBarTitleDisplayMode(.inline)
        .calendarEditSheet($editing)
        .calendarDeleteDialog($pendingDelete, errorMessage: $errorMessage)
        .errorAlert($errorMessage)
    }
}

extension View {
    /// Swipe right on a calendar row to edit it.
    func calendarEditSwipe(_ calendar: EKCalendar, editing: Binding<EKCalendar?>) -> some View {
        modifier(CalendarEditSwipe(calendar: calendar, editing: editing))
    }

    /// The edit form for the calendar swiped.
    func calendarEditSheet(_ calendar: Binding<EKCalendar?>) -> some View {
        sheet(item: Binding(
            get: { calendar.wrappedValue.map(EditedCalendar.init) },
            set: { calendar.wrappedValue = $0?.calendar }
        )) { item in
            NavigationStack {
                NewCalendarView(editing: item.calendar) { _ in calendar.wrappedValue = nil }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { calendar.wrappedValue = nil } label: { Image(systemName: "xmark") }
                        }
                    }
            }
        }
    }

    /// Asks before deleting a calendar, because its events go with it.
    func calendarDeleteDialog(_ calendar: Binding<EKCalendar?>, errorMessage: Binding<String?>) -> some View {
        modifier(CalendarDeleteDialog(calendar: calendar, errorMessage: errorMessage))
    }
}

private struct EditedCalendar: Identifiable {
    let calendar: EKCalendar
    var id: String { calendar.calendarIdentifier }
}

private struct CalendarEditSwipe: ViewModifier {
    let calendar: EKCalendar
    @Binding var editing: EKCalendar?
    @Environment(CalendarStore.self) private var store

    func body(content: Content) -> some View {
        content.swipeActions(edge: .leading) {
            if store.canEdit(calendar) {
                Button { editing = calendar } label: {
                    Image(systemName: "pencil.and.outline")
                }
                .tint(.brand)
            }
        }
    }
}

private struct CalendarDeleteDialog: ViewModifier {
    @Binding var calendar: EKCalendar?
    @Binding var errorMessage: String?
    @Environment(CalendarStore.self) private var store

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "「\(calendar?.title ?? "")」を削除すると、予定もすべて削除されます",
            isPresented: Binding(get: { calendar != nil }, set: { if !$0 { calendar = nil } }),
            titleVisibility: .visible,
            presenting: calendar
        ) { target in
            Button("カレンダーを削除", role: .destructive) {
                do { try store.deleteCalendar(target) } catch { errorMessage = error.localizedDescription }
            }
        }
    }
}

/// Adds a calendar, or with `editing` changes one's name and color.
struct NewCalendarView: View {
    var editing: EKCalendar? = nil
    var onCreated: (String) -> Void

    @Environment(CalendarStore.self) private var store
    @State private var title = ""
    @State private var color = ColorChoice()
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    init(editing: EKCalendar? = nil, onCreated: @escaping (String) -> Void) {
        self.editing = editing
        self.onCreated = onCreated
        if let editing {
            _title = State(initialValue: editing.title)
            _color = State(initialValue: ColorChoice(color: UIColor(cgColor: editing.cgColor)))
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("カレンダータイトル", text: $title)
                    .font(.system(size: 17 * 1.2, weight: .bold))
                    .focused($titleFocused)
            }
            Section("色") {
                ColorGrid(choice: $color)
            }
        }
        .navigationTitle(editing == nil ? "カレンダーを追加" : "カレンダーを編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: create) { Image(systemName: "checkmark") }
                    .buttonStyle(.glassProminent)
                    .tint(.brand)
            }
        }
        .onAppear { titleFocused = true }
        .errorAlert($errorMessage)
    }

    private func create() {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            if let editing {
                try store.updateCalendar(editing, title: name, color: color.uiColor)
                onCreated(editing.calendarIdentifier)
                return
            }
            let calendar = try store.createCalendar(title: name, color: color.uiColor)
            onCreated(calendar.calendarIdentifier)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A palette pick, or a free color from the last cell.
struct ColorChoice: Equatable {
    var paletteIndex: Int? = 0
    var custom = Color.purple

    var uiColor: UIColor {
        paletteIndex.map { CalendarPalette.colors[$0] } ?? UIColor(custom)
    }

    /// Starts from an existing color: its palette cell when it matches one, otherwise the free cell.
    init(color: UIColor? = nil) {
        guard let color else { return }
        if let index = CalendarPalette.colors.firstIndex(where: { $0.isClose(to: color) }) {
            paletteIndex = index
        } else {
            paletteIndex = nil
            custom = Color(uiColor: color)
        }
    }
}

private extension UIColor {
    func isClose(to other: UIColor) -> Bool {
        var a: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var b: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&a.0, green: &a.1, blue: &a.2, alpha: &a.3)
        other.getRed(&b.0, green: &b.1, blue: &b.2, alpha: &b.3)
        return abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) < 0.06
    }
}

/// Palette swatches in a grid; the bottom-right cell opens the system color picker.
struct ColorGrid: View {
    @Binding var choice: ColorChoice

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 14) {
            ForEach(CalendarPalette.colors.indices, id: \.self) { index in
                swatch(Color(uiColor: CalendarPalette.colors[index]), selected: choice.paletteIndex == index)
                    .onTapGesture { choice.paletteIndex = index }
            }
            ColorPicker("", selection: $choice.custom, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 34, height: 34)
                .overlay {
                    if choice.paletteIndex == nil {
                        Circle().stroke(Color.primary, lineWidth: 2).frame(width: 40, height: 40)
                    }
                }
                .onChange(of: choice.custom) { choice.paletteIndex = nil }
        }
        .padding(.vertical, 8)
    }

    private func swatch(_ color: Color, selected: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 34, height: 34)
            .overlay {
                if selected {
                    Circle().stroke(Color.primary, lineWidth: 2).frame(width: 40, height: 40)
                }
            }
            .frame(width: 40, height: 40)
            .contentShape(Circle())
    }
}

import EventKit
import SwiftUI

/// Every writable calendar; picking one (even the current one) goes straight back. Swipe left to delete.
struct CalendarPickerView: View {
    let selectedID: String?
    var onPick: (String) -> Void

    @Environment(CalendarStore.self) private var store
    @State private var pendingDelete: EKCalendar?
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
        .calendarDeleteDialog($pendingDelete, errorMessage: $errorMessage)
        .errorAlert($errorMessage)
    }
}

extension View {
    /// Asks before deleting a calendar, because its events go with it.
    func calendarDeleteDialog(_ calendar: Binding<EKCalendar?>, errorMessage: Binding<String?>) -> some View {
        modifier(CalendarDeleteDialog(calendar: calendar, errorMessage: errorMessage))
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

struct NewCalendarView: View {
    var onCreated: (String) -> Void

    @Environment(CalendarStore.self) private var store
    @State private var title = ""
    @State private var color = ColorChoice()
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

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
        .navigationTitle("カレンダーを追加")
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

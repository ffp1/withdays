import EventKit
import SwiftUI

/// Every writable calendar; picking one (even the current one) goes straight back.
struct CalendarPickerView: View {
    let selectedID: String?
    var onPick: (String) -> Void

    @Environment(CalendarStore.self) private var store

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
                    }
                }
            }
            Section {
                NavigationLink(value: EditorPath.newCalendar) {
                    Label("カレンダーを追加", systemImage: "plus")
                        .foregroundStyle(Color.brand)
                }
            }
        }
        .navigationTitle("カレンダー")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NewCalendarView: View {
    var onCreated: (String) -> Void

    @Environment(CalendarStore.self) private var store
    @State private var title = ""
    /// Index into the palette, or nil for the free color.
    @State private var paletteIndex: Int? = 0
    @State private var customColor = Color.purple
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    private var color: UIColor {
        paletteIndex.map { CalendarPalette.colors[$0] } ?? UIColor(customColor)
    }

    var body: some View {
        Form {
            Section {
                TextField("カレンダータイトル", text: $title)
                    .focused($titleFocused)
            }
            Section("色") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 14) {
                    ForEach(CalendarPalette.colors.indices, id: \.self) { index in
                        swatch(Color(uiColor: CalendarPalette.colors[index]), selected: paletteIndex == index)
                            .onTapGesture { paletteIndex = index }
                    }
                    // The last cell picks any color.
                    ColorPicker("", selection: $customColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 34, height: 34)
                        .overlay {
                            if paletteIndex == nil {
                                Circle().stroke(Color.primary, lineWidth: 2).frame(width: 40, height: 40)
                            }
                        }
                        .onChange(of: customColor) { paletteIndex = nil }
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("カレンダーを追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: create) { Image(systemName: "checkmark") }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { titleFocused = true }
        .errorAlert($errorMessage)
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

    private func create() {
        do {
            let calendar = try store.createCalendar(title: title.trimmingCharacters(in: .whitespaces), color: color)
            onCreated(calendar.calendarIdentifier)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

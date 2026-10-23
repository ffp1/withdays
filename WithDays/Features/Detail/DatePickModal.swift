import SwiftUI

enum DateAction: String, Identifiable {
    case move, duplicate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .move: "移動先の日付"
        case .duplicate: "複製先の日付"
        }
    }
}

/// A month calendar for picking where to move (one day) or duplicate (several days) an event.
struct DatePickModal: View {
    let action: DateAction
    var onConfirm: ([Date]) -> Void

    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.weekStart) private var weekStart = 1

    private let originalDay: Date
    @State private var month: Date
    @State private var selection: Set<Date> = []

    init(action: DateAction, initialDate: Date, onConfirm: @escaping ([Date]) -> Void) {
        self.action = action
        self.onConfirm = onConfirm
        originalDay = CalendarMath.startOfDay(initialDate)
        _month = State(initialValue: CalendarMath.startOfMonth(initialDate))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    monthButton(-1, icon: "chevron.left")
                    Spacer()
                    Text(Fmt.monthTitle(month))
                        .font(.system(size: 18, weight: .bold))
                        .monospacedDigit()
                    Spacer()
                    monthButton(1, icon: "chevron.right")
                }
                .padding(.horizontal, 8)

                WeekdayHeader(weekStart: weekStart)
                grid

                Text(action == .move ? "移動先の日付を1つ選んでください" : "複製先の日付をタップして選んでください（複数可）")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    changeMonth(value.translation.width < 0 ? 1 : -1)
                }
            )
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onConfirm(selection.sorted())
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
    }

    private var grid: some View {
        let days = CalendarMath.gridDays(for: month, weekStart: weekStart)
        let holidays = store.holidays(from: days[0], to: CalendarMath.addDays(42, to: days[0]))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
            ForEach(days, id: \.self) { day in
                let isSelected = selection.contains(day)
                let inMonth = CalendarMath.isSameMonth(day, month)
                Button {
                    toggle(day)
                } label: {
                    Text("\(CalendarMath.day(day))")
                        .font(.system(size: 17, weight: isSelected ? .bold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color.white : Color.dayNumber(weekday: CalendarMath.weekday(day), isHoliday: holidays.contains(day)))
                        .frame(width: 42, height: 42)
                        .background {
                            if isSelected {
                                Circle().fill(Color.brand)
                            } else if day == originalDay {
                                Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                            }
                        }
                        .opacity(inMonth ? 1 : 0.35)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func monthButton(_ delta: Int, icon: String) -> some View {
        Button { changeMonth(delta) } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private func changeMonth(_ delta: Int) {
        withAnimation(.snappy) { month = CalendarMath.addMonths(delta, to: month) }
    }

    private func toggle(_ day: Date) {
        switch action {
        case .move:
            selection = [day]
        case .duplicate:
            if selection.contains(day) { selection.remove(day) } else { selection.insert(day) }
        }
    }
}

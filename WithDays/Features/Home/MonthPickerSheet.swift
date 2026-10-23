import SwiftUI

/// Year + 4×3 month grid. Swipe, the chevrons, or anywhere in the side margins change the year.
struct MonthPickerSheet: View {
    let selected: Date
    var onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var year: Int

    init(selected: Date, onPick: @escaping (Date) -> Void) {
        self.selected = selected
        self.onPick = onPick
        _year = State(initialValue: CalendarMath.calendar.component(.year, from: selected))
    }

    private var selectedYear: Int { CalendarMath.calendar.component(.year, from: selected) }
    private var selectedMonth: Int { CalendarMath.calendar.component(.month, from: selected) }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                sideButton(-1, icon: "chevron.left")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 18) {
                    ForEach(1...12, id: \.self) { month in
                        let isSelected = year == selectedYear && month == selectedMonth
                        Button {
                            pick(month)
                        } label: {
                            Text("\(month)")
                                .font(.system(size: 20, weight: isSelected ? .bold : .regular))
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .frame(width: 52, height: 52)
                                .background {
                                    if isSelected { Circle().fill(Color.brand) }
                                }
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                sideButton(1, icon: "chevron.right")
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 12)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    change(value.translation.width < 0 ? 1 : -1)
                }
            )
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(String(year))
                        .font(.system(size: 20, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(year)))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func sideButton(_ delta: Int, icon: String) -> some View {
        Button {
            change(delta)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 48)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func change(_ delta: Int) {
        withAnimation(.snappy) { year += delta }
    }

    private func pick(_ month: Int) {
        if let date = CalendarMath.calendar.date(from: DateComponents(year: year, month: month, day: 1)) {
            onPick(date)
        }
        dismiss()
    }
}

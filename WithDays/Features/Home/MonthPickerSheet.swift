import SwiftUI

/// Year + 4×3 month grid. Swipe, the chevrons, or anywhere in the side margins change the year.
struct MonthPickerSheet: View {
    let selected: Date
    var onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    /// Direction of the last year change, so the grid slides the right way.
    @State private var forward = true

    private let cellWidth: CGFloat = 66
    private let cellHeight: CGFloat = 60
    private let rowSpacing: CGFloat = 8

    init(selected: Date, onPick: @escaping (Date) -> Void) {
        self.selected = selected
        self.onPick = onPick
        _year = State(initialValue: CalendarMath.calendar.component(.year, from: selected))
    }

    private var selectedYear: Int { CalendarMath.calendar.component(.year, from: selected) }
    private var selectedMonth: Int { CalendarMath.calendar.component(.month, from: selected) }
    private var thisYear: Int { CalendarMath.calendar.component(.year, from: .now) }
    private var thisMonth: Int { CalendarMath.calendar.component(.month, from: .now) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(String(year))
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(year)))
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            HStack(spacing: 0) {
                sideArea(-1, icon: "chevron.left")
                ZStack {
                    monthGrid
                        .id(year)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                        ))
                }
                .frame(width: cellWidth * 4, height: cellHeight * 3 + rowSpacing * 2)
                .clipped()
                sideArea(1, icon: "chevron.right")
            }
            .frame(maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                change(value.translation.width < 0 ? 1 : -1)
            }
        )
    }

    private var monthGrid: some View {
        VStack(spacing: rowSpacing) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(1...4, id: \.self) { column in
                        monthCell(row * 4 + column)
                    }
                }
            }
        }
    }

    private func monthCell(_ month: Int) -> some View {
        let isSelected = year == selectedYear && month == selectedMonth
        let isThisMonth = year == thisYear && month == thisMonth
        return Button {
            pick(month)
        } label: {
            Text("\(month)")
                .font(.system(size: 20, weight: isSelected ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : isThisMonth ? Color.brand : Color.primary)
                .frame(width: 50, height: 50)
                .background {
                    if isSelected { Circle().fill(Color.brand) }
                }
                .frame(width: cellWidth, height: cellHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sideArea(_ delta: Int, icon: String) -> some View {
        Button {
            change(delta)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func change(_ delta: Int) {
        forward = delta > 0
        // Let the new direction reach the outgoing grid before it animates away.
        Task { @MainActor in
            withAnimation(.snappy) { year += delta }
        }
    }

    private func pick(_ month: Int) {
        if let date = CalendarMath.calendar.date(from: DateComponents(year: year, month: month, day: 1)) {
            onPick(date)
        }
        dismiss()
    }
}

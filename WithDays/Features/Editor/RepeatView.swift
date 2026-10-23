import SwiftUI

struct RepeatView: View {
    @Binding var recurrence: Recurrence
    var onOpenMonthly: () -> Void

    @AppStorage(SettingsKey.weekStart) private var weekStart = 1

    var body: some View {
        List {
            ForEach(RepeatFrequency.allCases, id: \.self) { frequency in
                checkRow(frequency.label, checked: recurrence.frequency == frequency) {
                    select(frequency)
                }

                if frequency == .weekly, recurrence.frequency == .weekly {
                    ForEach(CalendarMath.orderedWeekdays(weekStart: weekStart), id: \.self) { weekday in
                        checkRow("\(CalendarMath.weekdaySymbols[weekday - 1])曜日", checked: recurrence.weekdays.contains(weekday), indented: true) {
                            toggle(weekday)
                        }
                    }
                }

                if frequency == .monthly, recurrence.frequency == .monthly {
                    Button(action: onOpenMonthly) {
                        HStack {
                            Text("くりかえし条件")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(recurrence.monthlySummary ?? "なし")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.leading, 24)
                        .contentShape(Rectangle())
                    }
                }
            }
        }
        .navigationTitle("くりかえし")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func checkRow(_ label: String, checked: Bool, indented: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                if checked { CheckMark() }
            }
            .padding(.leading, indented ? 24 : 0)
            .contentShape(Rectangle())
        }
    }

    private func select(_ frequency: RepeatFrequency) {
        let previous = recurrence.frequency
        withAnimation { recurrence.frequency = frequency }
        if frequency == .weekly, recurrence.weekdays.isEmpty {
            recurrence.weekdays = [2]
        }
        // Choosing 毎月 goes straight on to its condition screen.
        if frequency == .monthly, previous != .monthly {
            onOpenMonthly()
        }
    }

    private func toggle(_ weekday: Int) {
        if recurrence.weekdays.contains(weekday) {
            // Keep at least one day.
            if recurrence.weekdays.count > 1 { recurrence.weekdays.remove(weekday) }
        } else {
            recurrence.weekdays.insert(weekday)
        }
    }
}

/// 「くりかえし条件」: なし, a 1–31 day grid, or an ordinal weekday wheel. One of the three applies.
struct MonthlyRuleView: View {
    @Binding var recurrence: Recurrence

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Button {
                    recurrence.monthlyMode = .sameDay
                } label: {
                    HStack {
                        Text("なし").foregroundStyle(.primary)
                        Spacer()
                        if recurrence.monthlyMode == .sameDay { CheckMark() }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(box)
                }
                .buttonStyle(.plain)

                VStack(spacing: 10) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                        ForEach(1...31, id: \.self) { day in
                            let on = recurrence.monthlyMode == .days && recurrence.monthDays.contains(day)
                            Button {
                                toggle(day)
                            } label: {
                                Text("\(day)")
                                    .font(.system(size: 16, weight: on ? .bold : .regular))
                                    .monospacedDigit()
                                    .foregroundStyle(on ? Color.white : Color.primary)
                                    .frame(width: 38, height: 38)
                                    .background {
                                        if on { Circle().fill(Color.brand) }
                                    }
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("31日を選ぶと、31日がない月は月末になります。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(box)

                HStack(spacing: 0) {
                    Button {
                        recurrence.monthlyMode = .ordinal
                    } label: {
                        Image(systemName: recurrence.monthlyMode == .ordinal ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(recurrence.monthlyMode == .ordinal ? Color.brand : Color.secondary)
                            .frame(width: 52)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Picker("", selection: $recurrence.ordinal) {
                        ForEach(Recurrence.ordinals, id: \.self) { ordinal in
                            Text(Recurrence.ordinalLabel(ordinal)).tag(ordinal)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Picker("", selection: $recurrence.ordinalDay) {
                        ForEach(OrdinalDay.all, id: \.self) { day in
                            Text(day.label).tag(day)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                .frame(height: 160)
                .background(box)
                .onChange(of: recurrence.ordinal) { recurrence.monthlyMode = .ordinal }
                .onChange(of: recurrence.ordinalDay) { recurrence.monthlyMode = .ordinal }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("くりかえし条件")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var box: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
    }

    private func toggle(_ day: Int) {
        if recurrence.monthlyMode != .days {
            recurrence.monthlyMode = .days
            recurrence.monthDays = [day]
        } else if recurrence.monthDays.contains(day) {
            recurrence.monthDays.remove(day)
            if recurrence.monthDays.isEmpty { recurrence.monthlyMode = .sameDay }
        } else {
            recurrence.monthDays.insert(day)
        }
    }
}

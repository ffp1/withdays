import EventKit
import SwiftUI
import UniformTypeIdentifiers

enum GridMetrics {
    static let weekdayHeight: CGFloat = 22
    static let rowHeight: CGFloat = 70
    /// Where the first event line starts inside a day, below the number and its underline.
    static let laneTop: CGFloat = 23
    static let laneHeight: CGFloat = 15
    static var height: CGFloat { weekdayHeight + rowHeight * 6 }
}

/// One month: weekday header plus six week rows.
struct MonthGridView: View {
    let month: Date
    @Binding var selectedDate: Date
    var onEventLongPress: (EKEvent) -> Void
    var onEmptyLongPress: (Date) -> Void
    var onDayDoubleTap: (Date) -> Void
    var onTemplateDrop: (UUID, Date) -> Void

    @Environment(CalendarStore.self) private var store
    @AppStorage(SettingsKey.weekStart) private var weekStart = 1

    var body: some View {
        let days = CalendarMath.gridDays(for: month, weekStart: weekStart)
        let end = CalendarMath.addDays(42, to: days[0])
        let events = store.events(from: days[0], to: end)
        let holidays = store.holidays(from: days[0], to: end)

        VStack(spacing: 0) {
            WeekdayHeader(weekStart: weekStart)
            ForEach(0..<6, id: \.self) { index in
                let week = Array(days[index * 7 ..< index * 7 + 7])
                WeekRow(
                    week: week,
                    month: month,
                    placed: WeekLayout.place(events, in: week),
                    holidays: holidays,
                    selectedDate: $selectedDate,
                    onEventLongPress: onEventLongPress,
                    onEmptyLongPress: onEmptyLongPress,
                    onDayDoubleTap: onDayDoubleTap,
                    onTemplateDrop: onTemplateDrop
                )
            }
        }
    }
}

struct WeekdayHeader: View {
    let weekStart: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CalendarMath.orderedWeekdays(weekStart: weekStart), id: \.self) { weekday in
                Text(CalendarMath.weekdaySymbols[weekday - 1])
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dayNumber(weekday: weekday, isHoliday: false))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: GridMetrics.weekdayHeight)
    }
}

private struct WeekRow: View {
    let week: [Date]
    let month: Date
    let placed: [PlacedEvent]
    let holidays: Set<Date>
    @Binding var selectedDate: Date
    var onEventLongPress: (EKEvent) -> Void
    var onEmptyLongPress: (Date) -> Void
    var onDayDoubleTap: (Date) -> Void
    var onTemplateDrop: (UUID, Date) -> Void

    @State private var dropColumn: Int?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width / 7
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                        DayCell(
                            day: day,
                            inMonth: CalendarMath.isSameMonth(day, month),
                            isHoliday: holidays.contains(day),
                            isSelected: CalendarMath.isSameDay(day, selectedDate),
                            isToday: CalendarMath.isSameDay(day, .now),
                            isDropTarget: dropColumn == index
                        )
                        .frame(width: width, height: GridMetrics.rowHeight, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedDate = day }
                        .simultaneousGesture(TapGesture(count: 2).onEnded { onDayDoubleTap(day) })
                        .onLongPressGesture { onEmptyLongPress(day) }
                        .zIndex(CalendarMath.isSameDay(day, .now) ? 1 : 0)
                    }
                }

                ForEach(placed) { item in
                    let top = GridMetrics.laneTop + CGFloat(item.lane) * GridMetrics.laneHeight
                    // Only lines that fit completely; the row is not clipped so today's number can grow past it.
                    if top + GridMetrics.laneHeight - 2 <= GridMetrics.rowHeight {
                        let span = CGFloat(item.endCol - item.startCol + 1)
                        let dayAt: (CGPoint) -> Date = { location in
                            week[min(item.endCol, item.startCol + Int(location.x / width))]
                        }
                        EventChip(
                            event: item.event,
                            isMultiDay: item.isMultiDay,
                            width: span * width - 4,
                            height: GridMetrics.laneHeight - 2
                        )
                        .opacity(CalendarMath.isSameMonth(week[item.startCol], month) || CalendarMath.isSameMonth(week[item.endCol], month) ? 1 : 0.45)
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { selectedDate = dayAt($0) }
                        .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { onDayDoubleTap(dayAt($0.location)) })
                        .onLongPressGesture { onEventLongPress(item.event) }
                        .offset(x: CGFloat(item.startCol) * width + 2, y: top)
                    }
                }
            }
            .onDrop(
                of: [.plainText],
                delegate: TemplateDropDelegate(columnWidth: width, week: week, column: $dropColumn, onDrop: onTemplateDrop)
            )
        }
        .frame(height: GridMetrics.rowHeight)
    }
}

extension EnvironmentValues {
    /// Bumped when 今月 is pressed while today is already selected; today's number then jumps and shakes.
    @Entry var todayPulse = 0
}

private struct PulseValues {
    var scale = 1.0
    var angle = 0.0
}

private struct DayCell: View {
    let day: Date
    let inMonth: Bool
    let isHoliday: Bool
    let isSelected: Bool
    let isToday: Bool
    let isDropTarget: Bool

    @Environment(\.todayPulse) private var todayPulse

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isDropTarget || isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isDropTarget ? Color.brand.opacity(0.16) : Color.primary.opacity(0.07))
                    .padding(1)
            }

            Rectangle()
                .fill(isSelected ? Color.brand : Color.dayLine)
                .frame(height: 1)
                .padding(.horizontal, 3)
                .offset(y: 20)

            // Today gets a filled circle over its number.
            Text("\(CalendarMath.day(day))")
                .font(.system(size: 12, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : Color.dayNumber(weekday: CalendarMath.weekday(day), isHoliday: isHoliday))
                .frame(minWidth: 18, minHeight: 18)
                .background {
                    if isToday { Circle().fill(Color.brand) }
                }
                .keyframeAnimator(initialValue: PulseValues(), trigger: isToday ? todayPulse : 0) { content, value in
                    content
                        .scaleEffect(value.scale)
                        .rotationEffect(.degrees(value.angle))
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        SpringKeyframe(1.7, duration: 0.22, spring: .bouncy)
                        LinearKeyframe(1.7, duration: 0.45)
                        SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
                    }
                    KeyframeTrack(\.angle) {
                        LinearKeyframe(0, duration: 0.18)
                        LinearKeyframe(-14, duration: 0.07)
                        LinearKeyframe(14, duration: 0.07)
                        LinearKeyframe(-12, duration: 0.07)
                        LinearKeyframe(12, duration: 0.07)
                        LinearKeyframe(-6, duration: 0.07)
                        LinearKeyframe(0, duration: 0.07)
                    }
                }
                .padding(.leading, 2)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(inMonth ? 1 : 0.35)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

/// An event line inside the grid. Text never wraps or truncates; it is simply cut off at the edge.
struct EventChip: View {
    let event: EKEvent
    let isMultiDay: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let filled = event.isAllDay
        let tinted = !filled && isMultiDay
        // A fixed-width frame keeps the overflowing text inside its own day(s) so the clip below cuts it off.
        Text(event.displayTitle)
            .font(.system(size: 10, weight: .bold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(filled ? Color.white : event.color)
            .padding(.horizontal, filled || tinted ? 5 : 1)
            .frame(width: width, height: height, alignment: .leading)
            .background {
                if filled {
                    Capsule().fill(event.color)
                } else if tinted {
                    Capsule().fill(event.color.opacity(0.18))
                }
            }
            .clipShape(filled || tinted ? AnyShape(Capsule()) : AnyShape(Rectangle()))
    }
}

struct PlacedEvent: Identifiable {
    let event: EKEvent
    let startCol: Int
    let endCol: Int
    let lane: Int
    let isMultiDay: Bool

    var id: String { "\(event.eventIdentifier ?? "")|\(event.startDate.timeIntervalSince1970)|\(startCol)" }
}

enum WeekLayout {
    /// Assigns each event in the week to the lowest free line, multi-day events first so their bars stay level.
    static func place(_ events: [EKEvent], in week: [Date]) -> [PlacedEvent] {
        guard let weekStart = week.first else { return [] }
        let weekEnd = CalendarMath.addDays(7, to: weekStart)

        struct Item {
            let event: EKEvent
            let startCol: Int
            let endCol: Int
            let isMultiDay: Bool
        }

        let items: [Item] = events.compactMap { event in
            // An event ending at 0:00 belongs to the previous day.
            let last = max(event.startDate, event.endDate.addingTimeInterval(-1))
            guard event.startDate < weekEnd, last >= weekStart else { return nil }
            return Item(
                event: event,
                startCol: max(0, CalendarMath.days(from: weekStart, to: event.startDate)),
                endCol: min(6, CalendarMath.days(from: weekStart, to: last)),
                isMultiDay: !CalendarMath.isSameDay(event.startDate, last)
            )
        }
        .sorted { a, b in
            if a.isMultiDay != b.isMultiDay { return a.isMultiDay }
            let spanA = a.endCol - a.startCol, spanB = b.endCol - b.startCol
            if spanA != spanB { return spanA > spanB }
            if a.event.isAllDay != b.event.isAllDay { return a.event.isAllDay }
            if a.event.startDate != b.event.startDate { return a.event.startDate < b.event.startDate }
            return (a.event.title ?? "") < (b.event.title ?? "")
        }

        var lanes: [[Bool]] = []
        var result: [PlacedEvent] = []
        for item in items {
            let columns = item.startCol...item.endCol
            var lane = 0
            while lane < lanes.count, columns.contains(where: { lanes[lane][$0] }) {
                lane += 1
            }
            if lane == lanes.count { lanes.append(Array(repeating: false, count: 7)) }
            for column in columns { lanes[lane][column] = true }
            result.append(PlacedEvent(event: item.event, startCol: item.startCol, endCol: item.endCol, lane: lane, isMultiDay: item.isMultiDay))
        }
        return result
    }
}

private struct TemplateDropDelegate: DropDelegate {
    let columnWidth: CGFloat
    let week: [Date]
    @Binding var column: Int?
    let onDrop: (UUID, Date) -> Void

    private func column(for info: DropInfo) -> Int {
        max(0, min(6, Int(info.location.x / columnWidth)))
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        column = column(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        column = column(for: info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        column = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let day = week[column(for: info)]
        column = nil
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? NSString, let id = TemplateTransfer.id(from: text as String) else { return }
            DispatchQueue.main.async { onDrop(id, day) }
        }
        return true
    }
}

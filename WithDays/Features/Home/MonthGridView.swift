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
    /// The today circle is 18pt; the day background's corners follow it.
    static let cornerRadius: CGFloat = 10
    static let longPress: Double = 0.5
}

extension EnvironmentValues {
    /// Week row height; the calendar grows into the list's space while moving / duplicating.
    @Entry var gridRowHeight: CGFloat = GridMetrics.rowHeight
}

enum RelocationKind {
    case move, duplicate
}

/// Moving or duplicating an event by picking days straight on the calendar.
struct Relocation: Equatable {
    let event: EKEvent
    let kind: RelocationKind
    var targets: Set<Date> = []
}

/// Everything the grid reports back to the home screen.
struct GridActions {
    var onDayTap: (Date) -> Void
    var onDayDoubleTap: (Date) -> Void
    var onDayLongPress: (Date) -> Void
    var onEventTap: (EKEvent, Date) -> Void
    var onEventLongPress: (EKEvent) -> Void
    var onTemplateDrop: (UUID, Date) -> Void
    /// Relocation: a tap toggles (duplicate) or sets (move) the target; a drag paints targets.
    var onTargetTap: (Date) -> Void
    var onTargetDrag: (Date) -> Void
}

/// One month: weekday header plus six week rows.
struct MonthGridView: View {
    let month: Date
    let selectedDate: Date
    let relocation: Relocation?
    let actions: GridActions

    @Environment(CalendarStore.self) private var store
    @Environment(\.gridRowHeight) private var rowHeight
    @AppStorage(SettingsKey.weekStart, store: AppGroup.defaults) private var weekStart = 1
    @State private var width: CGFloat = 0

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
                    placed: WeekLayout.place(events, in: week, relocation: relocation),
                    holidays: holidays,
                    selectedDate: selectedDate,
                    relocation: relocation,
                    actions: actions
                )
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // While relocating, dragging across the grid paints target days.
        .gesture(
            DragGesture(minimumDistance: 8).onChanged { value in
                guard width > 0 else { return }
                let row = Int((value.location.y - GridMetrics.weekdayHeight) / rowHeight)
                let column = Int(value.location.x / (width / 7))
                guard (0..<6).contains(row), (0..<7).contains(column) else { return }
                actions.onTargetDrag(days[row * 7 + column])
            },
            including: relocation == nil ? .subviews : .all
        )
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
    let selectedDate: Date
    let relocation: Relocation?
    let actions: GridActions

    @Environment(\.gridRowHeight) private var rowHeight
    @State private var dropColumn: Int?
    @AppStorage(SettingsKey.dimPastEvents) private var dimPast = false

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
                            isSelected: relocation == nil ? CalendarMath.isSameDay(day, selectedDate) : relocation?.targets.contains(day) == true,
                            isToday: CalendarMath.isSameDay(day, .now),
                            isDropTarget: dropColumn == index,
                            relocating: relocation != nil,
                            actions: actions
                        )
                        .frame(width: width, height: rowHeight, alignment: .topLeading)
                        .zIndex(CalendarMath.isSameDay(day, .now) ? 1 : 0)
                    }
                }

                ForEach(placed) { item in
                    let top = GridMetrics.laneTop + CGFloat(item.lane) * GridMetrics.laneHeight
                    // Only lines that fit completely; the row is not clipped so today's number can grow past it.
                    if top + GridMetrics.laneHeight - 2 <= rowHeight {
                        let span = CGFloat(item.endCol - item.startCol + 1)
                        let dayAt: (CGPoint) -> Date = { location in
                            week[min(item.endCol, item.startCol + Int(location.x / width))]
                        }
                        PressableChip(
                            item: item,
                            width: span * width - 4,
                            interactive: relocation == nil && !item.isPinned,
                            onTap: { actions.onEventTap(item.event, dayAt($0)) },
                            onDoubleTap: { actions.onDayDoubleTap(dayAt($0)) },
                            onLongPress: { actions.onEventLongPress(item.event) }
                        )
                        .opacity(chipOpacity(item))
                        .offset(x: CGFloat(item.startCol) * width + 2, y: top)
                    }
                }
            }
            .onDrop(
                of: [.plainText],
                delegate: TemplateDropDelegate(columnWidth: width, week: week, column: $dropColumn, onDrop: actions.onTemplateDrop)
            )
        }
        .frame(height: rowHeight)
    }

    private func chipOpacity(_ item: PlacedEvent) -> Double {
        if item.isPinned { return 1 }
        // While moving / duplicating, only the chosen event (and its previews) stay solid.
        if let relocation { return relocation.event == item.event ? 1 : 0.25 }
        let inMonth = CalendarMath.isSameMonth(week[item.startCol], month) || CalendarMath.isSameMonth(week[item.endCol], month)
        let past = dimPast && item.event.endDate < .now
        return (inMonth ? 1 : 0.45) * (past ? 0.4 : 1)
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
    let relocating: Bool
    let actions: GridActions

    @Environment(\.todayPulse) private var todayPulse
    @State private var pressing = false
    @State private var indicatorVisible = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isDropTarget || isSelected {
                RoundedRectangle(cornerRadius: GridMetrics.cornerRadius, style: .continuous)
                    .fill(isDropTarget ? Color.brand.opacity(0.16) : Color.primary.opacity(0.07))
                    .padding(1)
            }

            // Long-press progress: the day's outline draws itself while held.
            RoundedRectangle(cornerRadius: GridMetrics.cornerRadius, style: .continuous)
                .trim(from: 0, to: pressing ? 1 : 0)
                .opacity(indicatorVisible ? 1 : 0)
                .stroke(Color.brand, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .padding(1)

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
                    // A quick burst of about 0.33 s. Cubic keyframes land exactly on 1.0.
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(1.35, duration: 0.1)
                        LinearKeyframe(1.35, duration: 0.1)
                        CubicKeyframe(1.0, duration: 0.13)
                    }
                    KeyframeTrack(\.angle) {
                        LinearKeyframe(-12, duration: 0.05)
                        LinearKeyframe(12, duration: 0.05)
                        LinearKeyframe(-10, duration: 0.05)
                        LinearKeyframe(10, duration: 0.05)
                        LinearKeyframe(-5, duration: 0.05)
                        LinearKeyframe(0, duration: 0.05)
                    }
                }
                .padding(.leading, 2)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(inMonth ? 1 : 0.35)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            if relocating { actions.onTargetTap(day) } else { actions.onDayTap(day) }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if !relocating { actions.onDayDoubleTap(day) }
        })
        .onLongPressGesture(minimumDuration: GridMetrics.longPress) {
            if !relocating { actions.onDayLongPress(day) }
        } onPressingChanged: { isPressing in
            pressProgress(isPressing && !relocating, $pressing, $indicatorVisible)
        }
    }
}

/// Starts the progress a moment after touch-down (so plain taps don't flash it); on release it fades out,
/// then resets out of sight.
private func pressProgress(_ isPressing: Bool, _ progress: Binding<Bool>, _ visible: Binding<Bool>) {
    var instant = Transaction()
    instant.disablesAnimations = true
    if isPressing {
        withTransaction(instant) { visible.wrappedValue = true }
        withAnimation(.linear(duration: GridMetrics.longPress - 0.1).delay(0.1)) { progress.wrappedValue = true }
    } else {
        withAnimation(.easeOut(duration: 0.25)) { visible.wrappedValue = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            withTransaction(instant) {
                progress.wrappedValue = false
                visible.wrappedValue = true
            }
        }
    }
}
    } else {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { value.wrappedValue = false }
    }
}

/// An event line with tap, double tap and a long press that draws an underline while held.
private struct PressableChip: View {
    let item: PlacedEvent
    let width: CGFloat
    let interactive: Bool
    var onTap: (CGPoint) -> Void
    var onDoubleTap: (CGPoint) -> Void
    var onLongPress: () -> Void

    @State private var pressing = false
    @State private var indicatorVisible = true

    var body: some View {
        EventChip(
            event: item.event,
            isMultiDay: item.isMultiDay,
            width: width,
            height: GridMetrics.laneHeight - 2
        )
        .overlay(alignment: .bottomLeading) {
            Capsule()
                .fill(Color.brand)
                .frame(width: pressing ? width : 0, height: 2)
                .opacity(indicatorVisible ? 1 : 0)
                .offset(y: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { onTap($0) }
        .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { onDoubleTap($0.location) })
        .onLongPressGesture(minimumDuration: GridMetrics.longPress) {
            onLongPress()
        } onPressingChanged: { isPressing in
            pressProgress(isPressing, $pressing, $indicatorVisible)
        }
        .allowsHitTesting(interactive)
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
    /// A preview of where a relocated event will land.
    var isPinned = false

    var id: String { "\(isPinned ? "pin" : "")\(event.eventIdentifier ?? "")|\(event.startDate.timeIntervalSince1970)|\(startCol)" }
}

enum WeekLayout {
    /// Assigns each event in the week to the lowest free line, multi-day events first so their bars stay level.
    /// Relocation targets get a preview of the event forced onto the top line; everything else moves down.
    static func place(_ events: [EKEvent], in week: [Date], relocation: Relocation? = nil) -> [PlacedEvent] {
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

        if let relocation {
            let pinnedColumns = week.indices.filter { relocation.targets.contains(week[$0]) }
            if !pinnedColumns.isEmpty {
                var top = Array(repeating: false, count: 7)
                for column in pinnedColumns {
                    top[column] = true
                    result.append(PlacedEvent(event: relocation.event, startCol: column, endCol: column, lane: 0, isMultiDay: false, isPinned: true))
                }
                lanes.append(top)
            }
        }

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

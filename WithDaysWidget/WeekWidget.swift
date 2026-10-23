import EventKit
import SwiftUI
import WidgetKit

@main
struct WithDaysWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeekWidget()
    }
}

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekWidget", provider: WeekProvider()) { entry in
            WeekWidgetView(entry: entry)
        }
        .configurationDisplayName("今週の予定")
        .description("今週の予定を表示します。日付をタップするとその日を開きます。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: Data

struct WeekEntry: TimelineEntry {
    let date: Date
    let days: [WeekDay]
    let hasAccess: Bool
}

struct WeekDay: Identifiable {
    let date: Date
    let isHoliday: Bool
    let events: [WeekEvent]

    var id: Date { date }
}

struct WeekEvent: Identifiable {
    let id: String
    let title: String
    let color: Color
    let isAllDay: Bool
}

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry {
        WeekEntry(date: .now, days: WeekLoader.emptyWeek(), hasAccess: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        completion(WeekLoader.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        // The app also reloads the widget whenever events change.
        let midnight = CalendarMath.addDays(1, to: CalendarMath.startOfDay(.now))
        completion(Timeline(entries: [WeekLoader.load()], policy: .after(midnight)))
    }
}

enum WeekLoader {
    /// Sunday-to-Saturday week containing today.
    static func weekDays() -> [Date] {
        let today = CalendarMath.startOfDay(.now)
        let start = CalendarMath.addDays(-(CalendarMath.weekday(today) - 1), to: today)
        return (0..<7).map { CalendarMath.addDays($0, to: start) }
    }

    static func emptyWeek() -> [WeekDay] {
        weekDays().map { WeekDay(date: $0, isHoliday: false, events: []) }
    }

    static func load() -> WeekEntry {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return WeekEntry(date: .now, days: emptyWeek(), hasAccess: false)
        }
        let store = EKEventStore()
        let days = weekDays()
        let end = CalendarMath.addDays(7, to: days[0])

        // Same holiday detection as the app: it only colors dates and is not listed as events.
        let calendars = store.calendars(for: .event)
        let holidayCalendar = calendars.first { $0.title.contains("祝日") }
            ?? calendars.first { $0.type == .subscription && $0.title.localizedCaseInsensitiveContains("holiday") }
        let visible = calendars.filter { $0.calendarIdentifier != holidayCalendar?.calendarIdentifier }

        let events = visible.isEmpty ? [] : store.events(matching: store.predicateForEvents(withStart: days[0], end: end, calendars: visible))

        var holidays = Set<Date>()
        if let holidayCalendar {
            let predicate = store.predicateForEvents(withStart: days[0], end: end, calendars: [holidayCalendar])
            for event in store.events(matching: predicate) {
                var day = CalendarMath.startOfDay(event.startDate)
                repeat {
                    holidays.insert(day)
                    day = CalendarMath.addDays(1, to: day)
                } while day < event.endDate
            }
        }

        let week = days.map { day in
            let next = CalendarMath.addDays(1, to: day)
            let todays = events
                .filter { $0.startDate < next && max($0.startDate, $0.endDate.addingTimeInterval(-1)) >= day }
                .sorted { a, b in
                    if a.isAllDay != b.isAllDay { return a.isAllDay }
                    return a.startDate < b.startDate
                }
                .map { event in
                    WeekEvent(
                        id: "\(event.eventIdentifier ?? "")-\(event.startDate.timeIntervalSince1970)",
                        title: event.title ?? "",
                        color: event.calendar.map { Color(cgColor: $0.cgColor) } ?? .gray,
                        isAllDay: event.isAllDay
                    )
                }
            return WeekDay(date: day, isHoliday: holidays.contains(day), events: todays)
        }
        return WeekEntry(date: .now, days: week, hasAccess: true)
    }
}

// MARK: Views

struct WeekWidgetView: View {
    let entry: WeekEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Fmt.monthTitle(entry.date))
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()

            HStack(spacing: 0) {
                ForEach(entry.days) { day in
                    let weekday = CalendarMath.weekday(day.date)
                    Text(CalendarMath.weekdaySymbols[weekday - 1])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.dayNumber(weekday: weekday, isHoliday: false))
                        .frame(maxWidth: .infinity)
                }
            }

            if entry.hasAccess {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(entry.days) { day in
                        Link(destination: DeepLink.url(for: day.date)) {
                            DayColumn(day: day)
                        }
                    }
                }
            } else {
                Text("WithDays を開いて、カレンダーへのアクセスを許可してください。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The app's theme setting isn't reachable without an App Group, so the widget is always light.
        .environment(\.colorScheme, .light)
        .containerBackground(for: .widget) {
            Color.white
        }
    }
}

private struct DayColumn: View {
    let day: WeekDay

    var body: some View {
        let isToday = CalendarMath.isSameDay(day.date, .now)
        VStack(alignment: .leading, spacing: 2) {
            Text("\(CalendarMath.day(day.date))")
                .font(.system(size: 11, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : Color.dayNumber(weekday: CalendarMath.weekday(day.date), isHoliday: day.isHoliday))
                .frame(minWidth: 16, minHeight: 16)
                .background {
                    if isToday { Circle().fill(Color.brand) }
                }
            Rectangle()
                .fill(Color.dayLine)
                .frame(height: 1)
            ForEach(day.events) { event in
                WidgetChip(event: event)
            }
        }
        .padding(.horizontal, 1.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
    }
}

/// Like the app's grid: no wrapping or ellipsis, the text is just cut off at the column edge.
private struct WidgetChip: View {
    let event: WeekEvent

    var body: some View {
        // The clear base takes the column width; the overlaid text can be wider and gets clipped.
        Color.clear
            .frame(height: 13)
            .overlay(alignment: .leading) {
                Text(event.title)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(event.isAllDay ? Color.white : event.color)
                    .padding(.horizontal, event.isAllDay ? 4 : 0)
            }
            .background {
                if event.isAllDay { Capsule().fill(event.color) }
            }
            .clipShape(event.isAllDay ? AnyShape(Capsule()) : AnyShape(Rectangle()))
    }
}

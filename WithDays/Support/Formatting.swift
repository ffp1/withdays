import Foundation

/// Date math on a fixed Gregorian calendar, so a device set to the Japanese era calendar still shows 2026.
enum CalendarMath {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = .current
        return calendar
    }()

    static let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    static func addDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func addMonths(_ months: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    static func months(from a: Date, to b: Date) -> Int {
        calendar.dateComponents([.month], from: startOfMonth(a), to: startOfMonth(b)).month ?? 0
    }

    static func days(from a: Date, to b: Date) -> Int {
        calendar.dateComponents([.day], from: startOfDay(a), to: startOfDay(b)).day ?? 0
    }

    static func weekday(_ date: Date) -> Int {
        calendar.component(.weekday, from: date)
    }

    static func day(_ date: Date) -> Int {
        calendar.component(.day, from: date)
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    static func isSameMonth(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, equalTo: b, toGranularity: .month)
    }

    /// The 42 days (6 weeks) shown for `month`, starting on `weekStart` (1 = Sunday, 2 = Monday).
    static func gridDays(for month: Date, weekStart: Int) -> [Date] {
        let first = startOfMonth(month)
        let lead = (weekday(first) - weekStart + 7) % 7
        let start = addDays(-lead, to: first)
        return (0..<42).map { addDays($0, to: start) }
    }

    /// Weekday numbers (1 = Sunday) in display order.
    static func orderedWeekdays(weekStart: Int) -> [Int] {
        (0..<7).map { (weekStart - 1 + $0) % 7 + 1 }
    }

    /// Today when it is in `month`, otherwise the 1st.
    static func defaultSelection(in month: Date) -> Date {
        let today = startOfDay(.now)
        return isSameMonth(today, month) ? today : startOfMonth(month)
    }
}

enum Fmt {
    private static func make(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = CalendarMath.calendar
        formatter.dateFormat = format
        return formatter
    }

    private static let monthTitleFormatter = make("yyyy年M月")
    private static let fullDateFormatter = make("yyyy年M月d日(E)")
    private static let timeFormatter = make("H:mm")

    /// 2026年9月
    static func monthTitle(_ date: Date) -> String { monthTitleFormatter.string(from: date) }

    /// 2026年10月26日(月)
    static func fullDate(_ date: Date) -> String { fullDateFormatter.string(from: date) }

    /// 10:30
    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }

    /// 2026年9月26日(月) 10:30～12:30, with the end date repeated when the event spans days.
    static func range(start: Date, end: Date, isAllDay: Bool) -> String {
        let sameDay = CalendarMath.isSameDay(start, end)
        if isAllDay {
            return sameDay ? fullDate(start) : "\(fullDate(start))～\(fullDate(end))"
        }
        if sameDay {
            return "\(fullDate(start)) \(time(start))～\(time(end))"
        }
        return "\(fullDate(start)) \(time(start))～\(fullDate(end)) \(time(end))"
    }
}

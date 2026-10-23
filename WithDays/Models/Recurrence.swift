import EventKit

enum RepeatFrequency: String, Codable, CaseIterable {
    case none, daily, weekly, monthly, yearly

    var label: String {
        switch self {
        case .none: "なし"
        case .daily: "毎日"
        case .weekly: "毎週"
        case .monthly: "毎月"
        case .yearly: "毎年"
        }
    }
}

/// How a monthly repeat picks its days.
enum MonthlyMode: String, Codable {
    /// Same day of month as the start date (「なし」).
    case sameDay
    /// Chosen days of the month from the 1–31 grid.
    case days
    /// 「最初の月曜日」 style.
    case ordinal
}

enum OrdinalDay: Codable, Hashable {
    /// 1 = Sunday … 7 = Saturday.
    case weekday(Int)
    case weekdays
    case weekend

    static let all: [OrdinalDay] = (1...7).map { .weekday($0) } + [.weekdays, .weekend]

    var label: String {
        switch self {
        case .weekday(let day): "\(CalendarMath.weekdaySymbols[day - 1])曜日"
        case .weekdays: "平日"
        case .weekend: "週末"
        }
    }
}

struct Recurrence: Codable, Equatable {
    var frequency: RepeatFrequency = .none
    /// Weekly days, 1 = Sunday … 7 = Saturday.
    var weekdays: Set<Int> = [2]
    var monthlyMode: MonthlyMode = .sameDay
    /// 1…31; 31 means the last day of the month.
    var monthDays: Set<Int> = []
    /// 1…5, or -1 for 「最後の」.
    var ordinal = 1
    var ordinalDay: OrdinalDay = .weekday(2)

    static let ordinals = [1, 2, 3, 4, 5, -1]

    static func ordinalLabel(_ ordinal: Int) -> String {
        switch ordinal {
        case -1: "最後の"
        case 1: "最初の"
        default: "\(ordinal)回目の"
        }
    }

    init() {}

    var summary: String {
        switch frequency {
        case .none, .daily, .yearly:
            return frequency.label
        case .weekly:
            let days = weekdays.sorted().map { CalendarMath.weekdaySymbols[$0 - 1] }
            return days.isEmpty ? "毎週" : "毎週 " + days.joined(separator: "・")
        case .monthly:
            return monthlySummary.map { "毎月 " + $0 } ?? "毎月"
        }
    }

    /// The condition part shown on the 「くりかえし条件」 row.
    var monthlySummary: String? {
        switch monthlyMode {
        case .sameDay:
            return nil
        case .days:
            guard !monthDays.isEmpty else { return nil }
            return monthDays.sorted().map { $0 == 31 ? "末日" : "\($0)日" }.joined(separator: "・")
        case .ordinal:
            return Recurrence.ordinalLabel(ordinal) + ordinalDay.label
        }
    }

    var rule: EKRecurrenceRule? {
        func dayOfWeek(_ day: Int, week: Int = 0) -> EKRecurrenceDayOfWeek {
            EKRecurrenceDayOfWeek(dayOfTheWeek: EKWeekday(rawValue: day) ?? .monday, weekNumber: week)
        }
        func make(
            _ frequency: EKRecurrenceFrequency,
            daysOfTheWeek: [EKRecurrenceDayOfWeek]? = nil,
            daysOfTheMonth: [NSNumber]? = nil,
            setPositions: [NSNumber]? = nil
        ) -> EKRecurrenceRule {
            EKRecurrenceRule(
                recurrenceWith: frequency,
                interval: 1,
                daysOfTheWeek: daysOfTheWeek,
                daysOfTheMonth: daysOfTheMonth,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: setPositions,
                end: nil
            )
        }

        switch frequency {
        case .none:
            return nil
        case .daily:
            return make(.daily)
        case .weekly:
            return make(.weekly, daysOfTheWeek: weekdays.isEmpty ? nil : weekdays.sorted().map { dayOfWeek($0) })
        case .yearly:
            return make(.yearly)
        case .monthly:
            switch monthlyMode {
            case .sameDay:
                return make(.monthly)
            case .days:
                guard !monthDays.isEmpty else { return make(.monthly) }
                // -1 is the last day of the month, so 31 falls back to 30 (or Feb's last day) in short months.
                return make(.monthly, daysOfTheMonth: monthDays.sorted().map { NSNumber(value: $0 == 31 ? -1 : $0) })
            case .ordinal:
                switch ordinalDay {
                case .weekday(let day):
                    return make(.monthly, daysOfTheWeek: [dayOfWeek(day, week: ordinal)])
                case .weekdays:
                    return make(.monthly, daysOfTheWeek: (2...6).map { dayOfWeek($0) }, setPositions: [NSNumber(value: ordinal)])
                case .weekend:
                    return make(.monthly, daysOfTheWeek: [1, 7].map { dayOfWeek($0) }, setPositions: [NSNumber(value: ordinal)])
                }
            }
        }
    }

    init(rule: EKRecurrenceRule?) {
        guard let rule else { return }
        switch rule.frequency {
        case .daily:
            frequency = .daily
        case .weekly:
            frequency = .weekly
            weekdays = Set((rule.daysOfTheWeek ?? []).map { $0.dayOfTheWeek.rawValue })
        case .monthly:
            frequency = .monthly
            if let days = rule.daysOfTheMonth, !days.isEmpty {
                monthlyMode = .days
                monthDays = Set(days.map { $0.intValue < 0 ? 31 : $0.intValue })
            } else if let days = rule.daysOfTheWeek, let first = days.first {
                monthlyMode = .ordinal
                let set = Set(days.map { $0.dayOfTheWeek.rawValue })
                let position = rule.setPositions?.first?.intValue ?? first.weekNumber
                ordinal = Recurrence.ordinals.contains(position) ? position : 1
                if set == [2, 3, 4, 5, 6] {
                    ordinalDay = .weekdays
                } else if set == [1, 7] {
                    ordinalDay = .weekend
                } else {
                    ordinalDay = .weekday(first.dayOfTheWeek.rawValue)
                }
            }
        case .yearly:
            frequency = .yearly
        @unknown default:
            break
        }
    }
}

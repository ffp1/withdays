import EventKit

/// The editable fields of an event, detached from EventKit so templates can store it too.
struct EventDraft: Codable, Equatable {
    var title = ""
    var calendarID: String?
    var isAllDay = false
    var start: Date
    var end: Date
    var recurrence = Recurrence()
    var location = ""
    var url = ""
    var notes = ""

    /// A one-hour event on `day`, starting at the next full hour.
    init(day: Date) {
        let hour = min(CalendarMath.calendar.component(.hour, from: .now) + 1, 23)
        start = CalendarMath.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        end = start.addingTimeInterval(3600)
    }

    init(event: EKEvent) {
        title = event.title ?? ""
        calendarID = event.calendar?.calendarIdentifier
        isAllDay = event.isAllDay
        start = event.startDate
        end = event.endDate
        recurrence = Recurrence(rule: event.recurrenceRules?.first)
        location = event.location ?? ""
        url = event.url?.absoluteString ?? ""
        notes = event.notes ?? ""
    }

    /// The same content moved to `day`, keeping the time of day and the length.
    func placed(on day: Date) -> EventDraft {
        let offset = CalendarMath.days(from: start, to: day)
        var copy = self
        copy.start = CalendarMath.addDays(offset, to: start)
        copy.end = CalendarMath.addDays(offset, to: end)
        return copy
    }

    func apply(to event: EKEvent, calendar: EKCalendar?) {
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let calendar { event.calendar = calendar }
        event.isAllDay = isAllDay
        if isAllDay {
            let first = CalendarMath.startOfDay(start)
            event.startDate = first
            event.endDate = max(CalendarMath.startOfDay(end), first)
        } else {
            event.startDate = start
            event.endDate = max(end, start)
        }
        let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
        event.location = place.isEmpty ? nil : place
        let link = url.trimmingCharacters(in: .whitespacesAndNewlines)
        event.url = link.isEmpty ? nil : URL(string: link)
        event.notes = notes.isEmpty ? nil : notes
        // Re-setting an unchanged rule on a single occurrence would rewrite the series, so only touch it on change.
        if event.eventIdentifier == nil || Recurrence(rule: event.recurrenceRules?.first) != recurrence {
            event.recurrenceRules = recurrence.rule.map { [$0] }
        }
    }
}

struct EventTemplate: Codable, Identifiable, Equatable {
    var id = UUID()
    var draft: EventDraft
}

/// Templates live only in this app (UserDefaults); events themselves live in Apple's calendar.
@MainActor
@Observable
final class TemplateStore {
    private(set) var templates: [EventTemplate] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: SettingsKey.templates),
           let saved = try? JSONDecoder().decode([EventTemplate].self, from: data) {
            templates = saved
        }
    }

    func template(id: UUID) -> EventTemplate? {
        templates.first { $0.id == id }
    }

    func upsert(_ template: EventTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
        persist()
    }

    func delete(id: UUID) {
        templates.removeAll { $0.id == id }
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        templates.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(data, forKey: SettingsKey.templates)
        }
    }
}

/// Drag payload for a template dropped onto a calendar day.
enum TemplateTransfer {
    private static let prefix = "withdays-template:"

    static func payload(_ id: UUID) -> String { prefix + id.uuidString }

    static func id(from payload: String) -> UUID? {
        guard payload.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(prefix.count)))
    }
}

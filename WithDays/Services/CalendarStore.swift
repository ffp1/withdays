import EventKit
import SwiftUI
import WidgetKit

enum CalendarAccess {
    case undetermined, granted, denied
}

/// Apple's calendar database is the source of truth; this wraps EventKit for the views.
@MainActor
@Observable
final class CalendarStore {
    @ObservationIgnored let eventStore = EKEventStore()

    private(set) var status = EKEventStore.authorizationStatus(for: .event)
    private(set) var calendars: [EKCalendar] = []
    /// Bumped on every change to the database; views that fetch events read it so they refresh.
    private(set) var revision = 0

    var hiddenCalendarIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(hiddenCalendarIDs), forKey: SettingsKey.hiddenCalendars)
            invalidate()
        }
    }

    /// Empty means "detect automatically".
    var holidayCalendarID: String {
        didSet {
            UserDefaults.standard.set(holidayCalendarID, forKey: SettingsKey.holidayCalendar)
            invalidate()
        }
    }

    /// Empty means the system default calendar.
    var defaultCalendarID: String {
        didSet { UserDefaults.standard.set(defaultCalendarID, forKey: SettingsKey.defaultCalendar) }
    }

    @ObservationIgnored private var eventCache: [String: [EKEvent]] = [:]
    @ObservationIgnored private var holidayCache: [String: Set<Date>] = [:]
    @ObservationIgnored private var historyCache: [EKEvent]?
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: SettingsKey.hiddenCalendars) ?? [])
        holidayCalendarID = defaults.string(forKey: SettingsKey.holidayCalendar) ?? ""
        defaultCalendarID = defaults.string(forKey: SettingsKey.defaultCalendar) ?? ""
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        if access == .granted { reload() }
    }

    // MARK: Access

    var access: CalendarAccess {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    func requestAccess() async {
        _ = try? await eventStore.requestFullAccessToEvents()
        refreshStatus()
    }

    func refreshStatus() {
        status = EKEventStore.authorizationStatus(for: .event)
        if access == .granted { reload() }
    }

    func reload() {
        calendars = eventStore.calendars(for: .event).sorted {
            ($0.source.title, $0.title) < ($1.source.title, $1.title)
        }
        invalidate()
    }

    private func invalidate() {
        eventCache.removeAll()
        holidayCache.removeAll()
        historyCache = nil
        revision += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Calendars

    var holidayCalendar: EKCalendar? {
        if !holidayCalendarID.isEmpty, let chosen = calendar(id: holidayCalendarID) { return chosen }
        return calendars.first { $0.title.contains("祝日") }
            ?? calendars.first { $0.type == .subscription && $0.title.localizedCaseInsensitiveContains("holiday") }
    }

    /// Calendars whose events appear in the grid and list (the holiday calendar only colors dates).
    var visibleCalendars: [EKCalendar] {
        let holidayID = holidayCalendar?.calendarIdentifier
        return calendars.filter {
            $0.calendarIdentifier != holidayID && !hiddenCalendarIDs.contains($0.calendarIdentifier)
        }
    }

    var displayableCalendars: [EKCalendar] {
        let holidayID = holidayCalendar?.calendarIdentifier
        return calendars.filter { $0.calendarIdentifier != holidayID }
    }

    var writableCalendars: [EKCalendar] {
        displayableCalendars.filter(\.allowsContentModifications)
    }

    var defaultCalendar: EKCalendar? {
        writableCalendars.first { $0.calendarIdentifier == defaultCalendarID }
            ?? eventStore.defaultCalendarForNewEvents
            ?? writableCalendars.first
    }

    func calendar(id: String?) -> EKCalendar? {
        guard let id else { return nil }
        return calendars.first { $0.calendarIdentifier == id }
    }

    struct CalendarGroup: Identifiable {
        let source: String
        let calendars: [EKCalendar]

        var id: String { source }
    }

    /// Groups calendars by account, keeping the account order.
    func grouped(_ list: [EKCalendar]) -> [CalendarGroup] {
        var order: [String] = []
        var groups: [String: [EKCalendar]] = [:]
        for calendar in list {
            let title = calendar.source.title
            if groups[title] == nil { order.append(title) }
            groups[title, default: []].append(calendar)
        }
        return order.map { CalendarGroup(source: $0, calendars: groups[$0] ?? []) }
    }

    func createCalendar(title: String, color: UIColor) throws -> EKCalendar {
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = title
        calendar.cgColor = color.cgColor
        guard let source = eventStore.defaultCalendarForNewEvents?.source
            ?? eventStore.sources.first(where: { $0.sourceType == .calDAV })
            ?? eventStore.sources.first(where: { $0.sourceType == .local })
        else { throw AppError(message: "カレンダーを追加できるアカウントが見つかりません。") }
        calendar.source = source
        try eventStore.saveCalendar(calendar, commit: true)
        reload()
        return calendar
    }

    // MARK: Events

    /// Events of visible calendars overlapping [start, end), in start order.
    func events(from start: Date, to end: Date) -> [EKEvent] {
        _ = revision
        let key = "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)"
        if let cached = eventCache[key] { return cached }
        let list = visibleCalendars
        guard !list.isEmpty else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: list)
        let result = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        eventCache[key] = result
        return result
    }

    /// Start-of-day dates in [start, end) that have a holiday.
    func holidays(from start: Date, to end: Date) -> Set<Date> {
        _ = revision
        guard let holidayCalendar else { return [] }
        let key = "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)"
        if let cached = holidayCache[key] { return cached }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: [holidayCalendar])
        var days = Set<Date>()
        for event in eventStore.events(matching: predicate) {
            var day = CalendarMath.startOfDay(event.startDate)
            repeat {
                days.insert(day)
                day = CalendarMath.addDays(1, to: day)
            } while day < event.endDate
        }
        holidayCache[key] = days
        return days
    }

    /// The holiday's name on `day`, e.g. 「文化の日」.
    func holidayName(on day: Date) -> String? {
        _ = revision
        guard let holidayCalendar else { return nil }
        let start = CalendarMath.startOfDay(day)
        let predicate = eventStore.predicateForEvents(withStart: start, end: CalendarMath.addDays(1, to: start), calendars: [holidayCalendar])
        return eventStore.events(matching: predicate).compactMap(\.title).first
    }

    /// EventKit caps a predicate at four years, so long ranges are fetched a year at a time.
    private func fetch(from start: Date, to end: Date, calendars list: [EKCalendar]) -> [EKEvent] {
        guard !list.isEmpty else { return [] }
        var result: [EKEvent] = []
        var chunkStart = start
        while chunkStart < end {
            let chunkEnd = min(CalendarMath.calendar.date(byAdding: .year, value: 1, to: chunkStart) ?? end, end)
            let predicate = eventStore.predicateForEvents(withStart: chunkStart, end: chunkEnd, calendars: list)
            // An event crossing a chunk boundary comes back twice; keep the copy from the chunk it starts in.
            result += eventStore.events(matching: predicate).filter { $0.startDate >= chunkStart }
            chunkStart = chunkEnd
        }
        return result
    }

    /// The latest past event for each distinct title containing `query`, newest first.
    func history(matching query: String, limit: Int = 6) -> [EKEvent] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        if historyCache == nil {
            let now = Date.now
            let start = CalendarMath.calendar.date(byAdding: .year, value: -3, to: now) ?? now
            historyCache = fetch(from: start, to: CalendarMath.addDays(1, to: now), calendars: displayableCalendars)
                .sorted { $0.startDate > $1.startDate }
        }
        var seen = Set<String>()
        var result: [EKEvent] = []
        for event in historyCache ?? [] {
            guard let title = event.title, title.localizedStandardContains(text), seen.insert(title).inserted else { continue }
            result.append(event)
            if result.count == limit { break }
        }
        return result
    }

    /// Events whose title, location or notes contain `query`, two years either side of today.
    func search(_ query: String) -> [EKEvent] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        let now = Date.now
        let start = CalendarMath.calendar.date(byAdding: .year, value: -2, to: now) ?? now
        let end = CalendarMath.calendar.date(byAdding: .year, value: 2, to: now) ?? now
        return fetch(from: start, to: end, calendars: visibleCalendars)
            .filter {
                ($0.title ?? "").localizedStandardContains(text)
                    || ($0.location ?? "").localizedStandardContains(text)
                    || ($0.notes ?? "").localizedStandardContains(text)
            }
            .sorted { $0.startDate < $1.startDate }
            .prefix(300)
            .map { $0 }
    }

    func save(_ draft: EventDraft, to event: EKEvent? = nil, span: EKSpan = .thisEvent) throws {
        let target = event ?? EKEvent(eventStore: eventStore)
        draft.apply(to: target, calendar: calendar(id: draft.calendarID) ?? defaultCalendar)
        try eventStore.save(target, span: span, commit: true)
        reload()
    }

    func delete(_ event: EKEvent, span: EKSpan = .thisEvent) throws {
        try eventStore.remove(event, span: span, commit: true)
        reload()
    }

    /// Moves to `day`, keeping the time of day and length.
    func move(_ event: EKEvent, to day: Date, span: EKSpan = .thisEvent) throws {
        let offset = CalendarMath.days(from: event.startDate, to: day)
        guard offset != 0 else { return }
        let start = CalendarMath.addDays(offset, to: event.startDate)
        let end = CalendarMath.addDays(offset, to: event.endDate)
        event.startDate = start
        event.endDate = end
        try eventStore.save(event, span: span, commit: true)
        reload()
    }

    /// One-off copies on each of `days`, keeping the time of day and length.
    func duplicate(_ event: EKEvent, to days: [Date]) throws {
        var draft = EventDraft(event: event)
        draft.recurrence = Recurrence()
        for day in days {
            let copy = EKEvent(eventStore: eventStore)
            draft.placed(on: day).apply(to: copy, calendar: event.calendar)
            try eventStore.save(copy, span: .thisEvent, commit: false)
        }
        try eventStore.commit()
        reload()
    }
}

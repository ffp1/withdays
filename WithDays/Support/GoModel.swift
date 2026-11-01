import Foundation

/// A "Go" preset: a name and up to ten times of day (HH:mm, ascending).
/// A preset saved without a name is "temp": it shows as TEMPORARY and expires after 24 hours.
struct GoPreset: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var times: [String]
    var createdAt: Date

    static let temporaryName = "temp"
    static let maxTimes = 10

    var isTemporary: Bool { name == Self.temporaryName }
}

struct GoState: Codable, Equatable {
    var presets: [GoPreset] = []
    var selected: String?
}

/// Go presets live in the App Group so the lock screen widget / Live Activity can read them.
enum GoData {
    private static let key = "goState"
    static let temporaryLifetime: TimeInterval = 24 * 60 * 60

    static func load() -> GoState {
        guard let data = AppGroup.defaults.data(forKey: key),
              var state = try? JSONDecoder().decode(GoState.self, from: data)
        else { return GoState() }
        expireTemporary(&state)
        return state
    }

    static func save(_ state: GoState) {
        if let data = try? JSONEncoder().encode(state) {
            AppGroup.defaults.set(data, forKey: key)
        }
    }

    /// Drops temporary presets older than a day; returns whether anything changed.
    @discardableResult
    static func expireTemporary(_ state: inout GoState, now: Date = .now) -> Bool {
        let before = state.presets.count
        state.presets.removeAll { $0.isTemporary && now.timeIntervalSince($0.createdAt) >= temporaryLifetime }
        if !state.presets.contains(where: { $0.id == state.selected }) {
            state.selected = ordered(state.presets).first?.id
        }
        return state.presets.count != before
    }

    /// Temporary presets first, then the rest in their saved order.
    static func ordered(_ presets: [GoPreset]) -> [GoPreset] {
        presets.filter(\.isTemporary) + presets.filter { !$0.isTemporary }
    }

    static func selectedPreset(in state: GoState) -> GoPreset? {
        state.presets.first { $0.id == state.selected }
    }

    /// The next of the preset's times after `now`; a time already past today counts for tomorrow.
    static func nextTarget(for preset: GoPreset, now: Date = .now) -> (date: Date, time: String)? {
        let calendar = CalendarMath.calendar
        return preset.times.compactMap { time -> (Date, String)? in
            guard let (hour, minute) = parse(time),
                  var date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
            else { return nil }
            if date <= now { date = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
            return (date, time)
        }
        .min { $0.0 < $1.0 }
        .map { (date: $0.0, time: $0.1) }
    }

    static func parse(_ time: String) -> (Int, Int)? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return (hour, minute)
    }

    static func format(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    static func newID() -> String {
        "preset-\(UUID().uuidString)"
    }
}

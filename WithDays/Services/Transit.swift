import CoreLocation
import Foundation

/// Transit API (api.transit.ls8h.com): place search and journeys, used to make a temporary Go preset from trains.
enum Transit {
    private static let base = URL(string: "https://api.transit.ls8h.com/api/v1/")!
    private static let timeZone = TimeZone(identifier: "Asia/Tokyo")!

    struct Place: Decodable, Identifiable, Hashable {
        let id: String
        /// "geo:<lat>,<lon>", usable as a journey's destination.
        let endpoint: String
        let name: String
        let kind: String
        let description: String?
    }

    struct Journey: Decodable {
        let departureSecs: Int
        let arrivalSecs: Int
        let durationSecs: Int
        let legs: [Leg]

        var rides: [Leg] { legs.filter { $0.kind == "transit" } }
        /// From boarding the first train to arriving; the walk to the station isn't counted.
        var rideSecs: Int { arrivalSecs - (rides.first?.departureSecs ?? departureSecs) }
    }

    struct Leg: Decodable {
        let kind: String
        let routeName: String?
        let tripId: String?
        let from: Stop
        let to: Stop
        /// Seconds from the service day's 0:00; past 86400 on the next day.
        let departureSecs: Int
    }

    /// One way to get there: the trains to take, each with its departure.
    struct Option: Identifiable {
        struct Ride: Hashable {
            let time: String
            let line: String
        }

        let id: String
        /// "池袋 - 新宿 - 新宿三丁目": where it boards, the transfers and the destination.
        let name: String
        let rides: [Ride]
        let arrival: String
        let minutes: Int
    }

    struct Stop: Decodable {
        let id: String
        let name: String
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Places: Decodable { let places: [Place] }
    private struct Plan: Decodable {
        let date: String
        let journeys: [Journey]
    }
    private struct ErrorBody: Decodable {
        struct Detail: Decodable { let message: String? }
        let error: Detail
    }

    static func suggest(_ query: String) async throws -> [Place] {
        try await get("places/suggest", [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "12")], as: Places.self).places
    }

    /// Ways from here to the place whose first train leaves after `start`, quickest first. The walk to the
    /// station doesn't push the trains later: searches start a while before `start` and keep the trains after it.
    /// A search returns six at most, so later searches start after the last departure until there are enough.
    static func options(from origin: CLLocationCoordinate2D, to place: Place, after start: Date, limit: Int) async throws -> [Option] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: start)
        let startSecs = (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
        var cursor = max(0, startSecs - 20 * 60)
        var date: String?
        var found: [String: Journey] = [:]

        for _ in 0..<6 where found.count < limit {
            var query = [
                URLQueryItem(name: "from", value: "geo:\(origin.latitude),\(origin.longitude)"),
                URLQueryItem(name: "to", value: place.endpoint),
                URLQueryItem(name: "toLabel", value: place.name),
                URLQueryItem(name: "time", value: clock(cursor)),
                URLQueryItem(name: "numItineraries", value: "6"),
            ]
            if let date { query.append(URLQueryItem(name: "date", value: date)) }
            let plan = try await get("plan", query, as: Plan.self)
            date = plan.date

            // Walking all the way isn't a train to catch, nor is one already gone.
            let trains = plan.journeys.filter { ($0.rides.first?.departureSecs ?? -1) >= startSecs }
            guard let last = plan.journeys.filter({ !$0.rides.isEmpty }).map(\.departureSecs).max() else { break }
            for journey in trains {
                let key = journey.rides.map { $0.tripId ?? "\($0.departureSecs)" }.joined(separator: "|")
                if found[key] == nil { found[key] = journey }
            }
            cursor = max(cursor, last) + 60
        }

        guard !found.isEmpty else { throw Failure(message: "電車の経路が見つかりませんでした") }
        return found
            .sorted { ($0.value.rideSecs, $0.value.departureSecs) < ($1.value.rideSecs, $1.value.departureSecs) }
            .prefix(limit)
            .map { entry in
                let journey = entry.value
                return Option(
                    id: entry.key,
                    name: title(of: journey, to: place),
                    rides: journey.rides.map { Option.Ride(time: time(of: $0.departureSecs), line: $0.routeName ?? "") },
                    arrival: time(of: journey.arrivalSecs),
                    minutes: Int((Double(journey.rideSecs) / 60).rounded())
                )
            }
    }

    private static func time(of secs: Int) -> String {
        GoData.format(hour: secs / 3600 % 24, minute: secs % 3600 / 60)
    }

    /// "池袋 - 新宿 - 新宿三丁目"
    private static func title(of journey: Journey, to place: Place) -> String {
        let stations = journey.rides.map(\.from.name) + [place.name]
        var names: [String] = []
        for station in stations {
            let name = station.hasSuffix("駅") ? String(station.dropLast()) : station
            if names.last != name { names.append(name) }
        }
        return names.joined(separator: " - ")
    }

    private static func clock(_ secs: Int) -> String {
        String(format: "%02d:%02d:%02d", secs / 3600, secs % 3600 / 60, secs % 60)
    }

    private static func get<T: Decodable>(_ path: String, _ query: [URLQueryItem], as type: T.Type) async throws -> T {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
            throw Failure(message: message ?? "経路を取得できませんでした")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// The phone's position once, asking for permission the first time.
enum Locator {
    static func current() async throws -> CLLocationCoordinate2D {
        // The session asks for permission and keeps it until we're done.
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        var tries = 0
        for try await update in CLLocationUpdate.liveUpdates() {
            if update.authorizationDenied || update.authorizationDeniedGlobally {
                throw Transit.Failure(message: "位置情報の利用が許可されていません。iPhoneの設定から許可してください")
            }
            guard let location = update.location else { continue }
            // The first close fix, or a rough one after a few.
            tries += 1
            if location.horizontalAccuracy <= 100 || tries >= 4 { return location.coordinate }
        }
        throw Transit.Failure(message: "現在地を取得できませんでした")
    }
}

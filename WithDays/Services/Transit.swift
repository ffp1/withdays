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
        let legs: [Leg]

        var rides: [Leg] { legs.filter { $0.kind == "transit" } }
    }

    struct Leg: Decodable {
        let kind: String
        let routeName: String?
        let from: Stop
        let to: Stop
        /// Seconds from the service day's 0:00; past 86400 on the next day.
        let departureSecs: Int
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

    /// The next trains along one route, up to `limit`: the first journey that rides a train sets the route
    /// (where it boards, on which line, where it gets off first); later searches add the following trains on it.
    /// The name lists the boarding station, the transfers and the destination.
    static func departures(from origin: CLLocationCoordinate2D, to place: Place, after start: Date, limit: Int) async throws -> (name: String, times: [String]) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: start)
        var cursor = (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
        var date: String?
        var route: String?
        var name = ""
        var trains: [Int] = []

        for _ in 0..<5 where trains.count < limit {
            var query = [
                URLQueryItem(name: "from", value: "geo:\(origin.latitude),\(origin.longitude)"),
                URLQueryItem(name: "to", value: place.endpoint),
                URLQueryItem(name: "toLabel", value: place.name),
                URLQueryItem(name: "time", value: clock(cursor)),
                URLQueryItem(name: "numItineraries", value: "5"),
            ]
            if let date { query.append(URLQueryItem(name: "date", value: date)) }
            let plan = try await get("plan", query, as: Plan.self)
            date = plan.date

            let before = trains.count
            for journey in plan.journeys {
                guard let first = journey.rides.first else { continue }
                let key = "\(first.from.id)|\(first.routeName ?? "")|\(first.to.id)"
                if route == nil {
                    route = key
                    name = title(of: journey, to: place)
                }
                guard key == route, trains.last.map({ first.departureSecs > $0 }) ?? true else { continue }
                trains.append(first.departureSecs)
                cursor = max(cursor, journey.departureSecs + 60)
            }
            // Nothing new: the route has no more trains today.
            if trains.count == before { break }
        }

        guard !trains.isEmpty else { throw Failure(message: "電車の経路が見つかりませんでした") }
        var times: [String] = []
        for secs in trains.prefix(limit) {
            let time = GoData.format(hour: secs / 3600 % 24, minute: secs % 3600 / 60)
            if times.last != time { times.append(time) }
        }
        return (name, times)
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

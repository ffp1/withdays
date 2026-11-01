import ActivityKit
import AppIntents
import Foundation

/// The Go countdown shown on the Lock Screen and in the Dynamic Island.
struct GoActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var target: Date
        /// The target time as shown, e.g. "13:05".
        var time: String
    }
}

/// Run from the lock screen widget: starts the Go countdown as a Live Activity, or ends it if one is showing.
/// A Live Activity intent runs in the app's process, so it works without unlocking the phone.
struct ToggleGoActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Goのカウントダウン"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        // Never runs here: the system performs Live Activity intents in the app.
        return .result()
        #else
        let running = Activity<GoActivityAttributes>.activities
        if !running.isEmpty {
            for activity in running {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return .result()
        }
        let state = GoData.load()
        guard let preset = GoData.selectedPreset(in: state),
              let next = GoData.nextTarget(for: preset)
        else { return .result() }
        let content = ActivityContent(
            state: GoActivityAttributes.ContentState(target: next.date, time: next.time),
            staleDate: next.date
        )
        _ = try Activity.request(attributes: GoActivityAttributes(), content: content)
        return .result()
        #endif
    }
}

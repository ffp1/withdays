import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Lock Screen 1×1: just the Go logo. Tapping it starts (or stops) the Go countdown as a Live Activity,
/// which shows on the Lock Screen without unlocking.
struct GoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GoWidget", provider: GoProvider()) { _ in
            GoWidgetView()
        }
        .configurationDisplayName("Go")
        .description("タップでロック画面にGoのカウントダウンを表示します。")
        .supportedFamilies([.accessoryCircular])
    }
}

struct GoEntry: TimelineEntry {
    let date: Date
}

struct GoProvider: TimelineProvider {
    func placeholder(in context: Context) -> GoEntry { GoEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (GoEntry) -> Void) {
        completion(GoEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GoEntry>) -> Void) {
        completion(Timeline(entries: [GoEntry(date: .now)], policy: .never))
    }
}

struct GoWidgetView: View {
    var body: some View {
        Button(intent: ToggleGoActivityIntent()) {
            Image("GoLogo")
                .resizable()
                .scaledToFit()
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .containerBackground(for: .widget) { Color.clear }
    }
}

/// The countdown itself: target time, then the time left (live, without the app running).
struct GoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GoActivityAttributes.self) { context in
            GoLockScreenView(state: context.state)
                // Dark backing so the white timer reads in light mode too.
                .activityBackgroundTint(Color.black.opacity(0.45))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "\(DeepLink.scheme)://go"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("GoLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundStyle(Color.brand)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.time)
                        .font(.system(size: 17, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(timerInterval: Date.now...max(.now, context.state.target), countsDown: true)
                        .font(.system(size: 40, weight: .thin))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                }
            } compactLeading: {
                Image("GoLogo")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.brand)
            } compactTrailing: {
                Text(timerInterval: Date.now...max(.now, context.state.target), countsDown: true)
                    .monospacedDigit()
                    .frame(width: 44)
                    .foregroundStyle(.white)
            } minimal: {
                Image("GoLogo")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.brand)
            }
            .widgetURL(URL(string: "\(DeepLink.scheme)://go"))
        }
    }
}

private struct GoLockScreenView: View {
    let state: GoActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 2) {
            Text(state.time)
                .font(.system(size: 20, weight: .light))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
            // Counts down by itself; the "分 / 秒" labels of the app can't be drawn on a live timer.
            Text(timerInterval: Date.now...max(.now, state.target), countsDown: true)
                .font(.system(size: 52, weight: .thin))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

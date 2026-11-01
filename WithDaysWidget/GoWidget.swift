import SwiftUI
import WidgetKit

/// Lock Screen 1×1: just the Go logo. Tapping it opens the app on Go.
struct GoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GoWidget", provider: GoProvider()) { _ in
            GoWidgetView()
        }
        .configurationDisplayName("Go")
        .description("タップでGoを開きます。")
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
        Image("GoLogo")
            .resizable()
            .scaledToFit()
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(URL(string: "\(DeepLink.scheme)://go"))
    }
}

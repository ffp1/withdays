import EventKit
import SwiftUI

/// Searches titles, locations and notes; tapping a result jumps to that day.
struct SearchView: View {
    var onSelect: (Date) -> Void

    @Environment(CalendarStore.self) private var store
    @State private var query = ""
    @State private var results: [EKEvent] = []

    private struct DayGroup: Identifiable {
        let day: Date
        let events: [EKEvent]

        var id: Date { day }
    }

    private var groups: [DayGroup] {
        var order: [Date] = []
        var byDay: [Date: [EKEvent]] = [:]
        for event in results {
            let day = CalendarMath.startOfDay(event.startDate)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(event)
        }
        return order.map { DayGroup(day: $0, events: byDay[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(groups) { group in
                Section(Fmt.fullDate(group.day)) {
                    ForEach(group.events, id: \.self) { event in
                        Button { onSelect(event.startDate) } label: { row(event) }
                    }
                }
            }
        }
        .overlay {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty, results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "タイトル・場所・メモ")
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            results = store.search(query)
        }
        .navigationTitle("検索")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ event: EKEvent) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                Text(event.isAllDay ? "終日" : "\(Fmt.time(event.startDate))～\(Fmt.time(event.endDate))")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

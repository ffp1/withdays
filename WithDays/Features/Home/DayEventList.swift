import EventKit
import SwiftUI

/// The selected day's events below the calendar.
struct DayEventList: View {
    let day: Date
    var onEdit: (EKEvent) -> Void
    var onDelete: (EKEvent) -> Void
    var onAdd: () -> Void

    @Environment(CalendarStore.self) private var store

    var body: some View {
        let start = CalendarMath.startOfDay(day)
        let end = CalendarMath.addDays(1, to: start)
        let events = store.events(from: start, to: end).sorted { a, b in
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            return a.startDate < b.startDate
        }

        List {
            if events.isEmpty {
                Text("予定はありません")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            }
            ForEach(events, id: \.self) { event in
                EventRow(event: event, dayStart: start, dayEnd: end)
                    .contentShape(Rectangle())
                    .onTapGesture { onEdit(event) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { onDelete(event) } label: {
                            Label("削除", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                    .swipeActions(edge: .leading) {
                        Button { onEdit(event) } label: {
                            Label("編集", systemImage: "pencil")
                        }
                        .tint(.gray)
                    }
            }

            Button(action: onAdd) {
                Label("予定を追加", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .contentMargins(.bottom, 96, for: .scrollContent)
    }
}

private struct EventRow: View {
    let event: EKEvent
    let dayStart: Date
    let dayEnd: Date

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            timeColumn
                .frame(width: 42)
                .frame(maxHeight: .infinity)

            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                if let location = event.location, !location.isEmpty {
                    detail(location, icon: "mappin.and.ellipse")
                }
                if let url = event.url {
                    detail(url.absoluteString, icon: "link")
                }
                if let notes = event.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var timeColumn: some View {
        let startsToday = event.startDate >= dayStart
        let endsToday = event.endDate <= dayEnd
        if event.isAllDay || (!startsToday && !endsToday) {
            Text("終日")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                Text(startsToday ? Fmt.time(event.startDate) : "")
                Spacer(minLength: 6)
                Text(endsToday ? Fmt.time(event.endDate) : "")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
        }
    }

    private func detail(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .labelStyle(DetailLabelStyle())
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct DetailLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 10))
            configuration.title
        }
    }
}

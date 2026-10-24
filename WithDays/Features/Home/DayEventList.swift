import EventKit
import SwiftUI

/// One day's events: a page of the day pager below the calendar.
/// Rows behave like any List row (tap, swipe actions); only the add row and the empty space below
/// hand sideways drags to the pager.
struct DayEventList: View {
    let day: Date
    var onEdit: (EKEvent) -> Void
    var onDelete: (EKEvent) -> Void
    var onRelocate: (EKEvent, RelocationKind) -> Void
    var onAdd: () -> Void
    var onPageDrag: (DragGesture.Value) -> Void
    var onPageDragEnd: (DragGesture.Value) -> Void

    @Environment(CalendarStore.self) private var store
    @State private var fillerHeight: CGFloat = 0

    /// The same space above and below every row, the first one included.
    private static let rowInsets = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)

    private var pageDrag: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onChanged(onPageDrag)
            .onEnded(onPageDragEnd)
    }

    var body: some View {
        let start = CalendarMath.startOfDay(day)
        let end = CalendarMath.addDays(1, to: start)
        let events = store.events(from: start, to: end).sorted { a, b in
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            return a.startDate < b.startDate
        }
        List {
            ForEach(events, id: \.self) { event in
                EventRow(event: event, dayStart: start, dayEnd: end)
                    .listRowSeparator(.visible, edges: .bottom)
                    // No line above the first row.
                    .listRowSeparator(event == events.first ? .hidden : .visible, edges: .top)
                    .listRowInsets(Self.rowInsets)
                    .contentShape(Rectangle())
                    .onTapGesture { onEdit(event) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { onDelete(event) } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                    }
                    // Swiping all the way runs the first action: duplicate.
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { onRelocate(event, .duplicate) } label: {
                            Image(systemName: "plus.square.on.square")
                        }
                        .tint(.gray)
                        Button { onRelocate(event, .move) } label: {
                            Image(systemName: "calendar.badge.clock")
                        }
                        .tint(Color(.systemGray2))
                        Button { onEdit(event) } label: {
                            Image(systemName: "pencil.and.outline")
                        }
                        .tint(.brand)
                    }
            }

            // A plain tap, not a Button: a sideways drag that starts here pages the day without adding.
            Label("予定を追加", systemImage: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture(perform: onAdd)
                .simultaneousGesture(pageDrag)
                // Hide only its own bottom line so the last event still gets a divider above this row.
                .listRowSeparator(.hidden, edges: .bottom)
                .listRowSeparator(events.isEmpty ? .hidden : .visible, edges: .top)
                .listRowInsets(Self.rowInsets)

            ListFiller(height: fillerHeight)
                .simultaneousGesture(pageDrag)
        }
        .listStyle(.plain)
        // Just enough to scroll the last row clear of the bottom buttons.
        .contentMargins(.bottom, 80, for: .scrollContent)
        .tracksFillerHeight($fillerHeight)
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
                    detail(location, icon: "map.fill")
                }
                if let url = event.url {
                    detail(url.absoluteString, icon: "link")
                }
                if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
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

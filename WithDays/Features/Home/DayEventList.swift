import EventKit
import SwiftUI

/// The selected day's events below the calendar. Dragging the empty space (or the add row)
/// sideways pages to the previous / next day, following the finger like the calendar's months.
struct DayEventList: View {
    let day: Date
    var onEdit: (EKEvent) -> Void
    var onDelete: (EKEvent) -> Void
    var onRelocate: (EKEvent, RelocationKind) -> Void
    var onAdd: () -> Void
    /// -1 / +1 once a swipe to the previous / next day has finished sliding.
    var onSwipeDay: (Int) -> Void

    @Environment(CalendarStore.self) private var store
    @State private var dragOffset: CGFloat = 0
    @State private var pageWidth: CGFloat = 0

    var body: some View {
        let today = CalendarMath.startOfDay(day)
        let pages = [-1, 0, 1].map { CalendarMath.addDays($0, to: today) }
        ZStack {
            ForEach(Array(pages.enumerated()), id: \.element) { index, pageDay in
                dayPage(pageDay)
                    .offset(x: CGFloat(index - 1) * pageWidth + dragOffset)
                    .allowsHitTesting(index == 1)
                    .transition(.opacity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        .clipped()
        // Picking a day on the calendar cross-fades (or slides, for an adjacent day).
        .animation(.easeInOut(duration: 0.2), value: today)
    }

    private func dayPage(_ start: Date) -> some View {
        let end = CalendarMath.addDays(1, to: start)
        let events = store.events(from: start, to: end).sorted { a, b in
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            return a.startDate < b.startDate
        }
        return List {
            ForEach(events, id: \.self) { event in
                EventRow(event: event, dayStart: start, dayEnd: end)
                    .listRowSeparator(.visible, edges: .bottom)
                    // No line above the first row.
                    .listRowSeparator(event == events.first ? .hidden : .visible, edges: .top)
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

            Button(action: onAdd) {
                Label("予定を追加", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(dayDrag)
            // Hide only its own bottom line so the last event still gets a divider above this row.
            .listRowSeparator(.hidden, edges: .bottom)
            .listRowSeparator(events.isEmpty ? .hidden : .visible, edges: .top)

            // Empty space below: also drags to the neighbouring day.
            Color.clear
                .frame(height: 240)
                .contentShape(Rectangle())
                .gesture(dayDrag)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .contentMargins(.bottom, 96, for: .scrollContent)
    }

    /// Follows the finger; past a quarter width (or a flick) it finishes the slide, then hands the new day up.
    private var dayDrag: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let width = max(pageWidth, 1)
                let moved = value.translation.width, flicked = value.predictedEndTranslation.width
                let delta = moved < -width / 4 || flicked < -width / 2 ? 1 : (moved > width / 4 || flicked > width / 2 ? -1 : 0)
                guard delta != 0 else {
                    withAnimation(.snappy(duration: 0.25)) { dragOffset = 0 }
                    return
                }
                withAnimation(.snappy(duration: 0.3)) {
                    dragOffset = -CGFloat(delta) * width
                } completion: {
                    // The neighbour page is already in place, so the swap itself must not animate.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        onSwipeDay(delta)
                        dragOffset = 0
                    }
                }
            }
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

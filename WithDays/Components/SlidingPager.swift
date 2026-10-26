import SwiftUI

/// A page and the pages either side of it.
struct PagerSlot<ID: Hashable>: Hashable {
    let id: ID
    /// -1 left, 0 current, 1 right.
    let slot: Int
}

/// Drives a `SlidingPager`: where the pages sit and how a drag or a jump finishes.
/// Lists are not put inside a horizontal scroll view on purpose: that steals the rows' swipe actions,
/// so only the drags the screen hands in (empty space, add row, date band) move the pages.
@MainActor
@Observable
final class PagerModel<ID: Hashable> {
    var offset: CGFloat = 0
    var width: CGFloat = 0
    /// A page jumped to directly (not a neighbour) takes the slot on its side while it slides in.
    var incoming: PagerSlot<ID>?
    /// The page a running slide is heading to.
    private(set) var target: ID?

    func slots(current: ID, previous: ID?, next: ID?) -> [PagerSlot<ID>] {
        if let incoming { return [PagerSlot(id: current, slot: 0), incoming] }
        var slots = [PagerSlot(id: current, slot: 0)]
        if let previous { slots.append(PagerSlot(id: previous, slot: -1)) }
        if let next { slots.append(PagerSlot(id: next, slot: 1)) }
        return slots
    }

    /// Follows the finger; at the first / last page it gives a little and springs back.
    func drag(_ value: DragGesture.Value, hasPrevious: Bool, hasNext: Bool) {
        guard incoming == nil, abs(value.translation.width) > abs(value.translation.height) else { return }
        let hasNeighbor = value.translation.width < 0 ? hasNext : hasPrevious
        offset = value.translation.width * (hasNeighbor ? 1 : 0.25)
    }

    /// Past a quarter width, or with a flick, it settles on the neighbour; otherwise it settles back.
    /// `onStart` runs as the slide begins (to update selection right away, like a scroll view's page change);
    /// `commit` runs once the pages have settled.
    func end(
        _ value: DragGesture.Value,
        previous: ID?,
        next: ID?,
        onStart: (ID) -> Void = { _ in },
        commit: @escaping (ID) -> Void
    ) {
        guard incoming == nil else { return }
        let page = max(width, 1)
        let moved = value.translation.width, flicked = value.predictedEndTranslation.width
        let side = moved < -page / 4 || flicked < -page / 2 ? 1 : (moved > page / 4 || flicked > page / 2 ? -1 : 0)
        guard side != 0, let target = side == 1 ? next : previous else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { offset = 0 }
            return
        }
        self.target = target
        onStart(target)
        finish(target, side: side, animation: .spring(response: 0.32, dampingFraction: 0.9), commit: commit)
    }

    /// Slides `id` in from `side` (1 from the right, -1 from the left), whether or not it's adjacent.
    func slide(to id: ID, side: Int, animation: Animation, commit: @escaping (ID) -> Void) {
        guard incoming == nil else {
            commit(id)
            return
        }
        incoming = PagerSlot(id: id, slot: side)
        finish(id, side: side, animation: animation, commit: commit)
    }

    private func finish(_ id: ID, side: Int, animation: Animation, commit: @escaping (ID) -> Void) {
        target = id
        withAnimation(animation) {
            offset = -CGFloat(side) * width
        } completion: {
            // The new page is already where the current one goes, so the swap itself must not animate.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                commit(id)
                self.incoming = nil
                self.offset = 0
                self.target = nil
            }
        }
    }
}

/// Lays the slots out side by side, shifted together by the model's offset.
struct SlidingPager<ID: Hashable, Page: View>: View {
    let model: PagerModel<ID>
    let slots: [PagerSlot<ID>]
    @ViewBuilder let page: (ID, Bool) -> Page

    var body: some View {
        ZStack {
            ForEach(slots, id: \.id) { slot in
                page(slot.id, slot.slot == 0)
                    .offset(x: CGFloat(slot.slot) * model.width + model.offset)
                    .allowsHitTesting(slot.slot == 0)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { model.width = $0 }
        .clipped()
    }
}

/// Empty space at the end of a list that only fills what the rows leave free, so the list never
/// gains extra scrolling; it carries the page drag (and whatever tap the screen wants there).
struct ListFiller: View {
    let height: CGFloat

    var body: some View {
        Color.clear
            .frame(height: max(height, 1))
            .contentShape(Rectangle())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
    }
}

extension View {
    /// Keeps `filler` at whatever height the list's visible area has left below its rows.
    func tracksFillerHeight(_ filler: Binding<CGFloat>) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geometry in
            // Space left between the content (filler included) and the visible area's edges.
            geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom - geometry.contentSize.height
        } action: { _, free in
            let next = max(0, filler.wrappedValue + free)
            if abs(next - filler.wrappedValue) > 0.5 { filler.wrappedValue = next }
        }
    }
}

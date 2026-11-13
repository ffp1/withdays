import Foundation

/// Undo / redo as snapshots of the document. Slides are value types whose arrays are copy-on-write,
/// so a snapshot only costs the slides that changed. At most `limit` steps are kept.
struct EditHistory<State: Equatable> {
    let limit: Int
    private(set) var undoStack: [State] = []
    private(set) var redoStack: [State] = []
    /// The last change that may absorb the next one (typing, a slider) and when it was.
    private var coalesceKey: String?
    private var coalesceTime = Date.distantPast

    init(limit: Int = 100) {
        self.limit = limit
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Records the state before a change. A change with the same key within `window` seconds of the last one
    /// joins that step instead of making a new one.
    mutating func record(_ before: State, coalesce key: String? = nil, now: Date = .now, window: TimeInterval = 1.0) {
        if let key, key == coalesceKey, now.timeIntervalSince(coalesceTime) < window {
            coalesceTime = now
            return
        }
        undoStack.append(before)
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        redoStack.removeAll()
        coalesceKey = key
        coalesceTime = now
    }

    /// The state to go back to; `current` becomes redoable.
    mutating func undo(from current: State) -> State? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        breakCoalescing()
        return previous
    }

    mutating func redo(from current: State) -> State? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        breakCoalescing()
        return next
    }

    /// The next change makes a step of its own.
    mutating func breakCoalescing() {
        coalesceKey = nil
    }

    mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        coalesceKey = nil
    }
}

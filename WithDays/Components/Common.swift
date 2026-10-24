import EventKit
import SwiftUI

/// A pending change to a repeating event, waiting for 「この予定のみ／今後すべて」.
struct SpanRequest: Identifiable {
    let id = UUID()
    let message: String
    var destructive = false
    let perform: (EKSpan) -> Void
}

extension View {
    func spanDialog(_ request: Binding<SpanRequest?>) -> some View {
        confirmationDialog(
            request.wrappedValue?.message ?? "",
            isPresented: Binding(
                get: { request.wrappedValue != nil },
                set: { if !$0 { request.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: request.wrappedValue
        ) { pending in
            Button("この予定のみ", role: pending.destructive ? .destructive : nil) { pending.perform(.thisEvent) }
            Button("今後のすべての予定", role: pending.destructive ? .destructive : nil) { pending.perform(.futureEvents) }
            Button("キャンセル", role: .cancel) {}
        }
    }

    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "エラー",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

extension EKEvent {
    var color: Color {
        guard let cgColor = calendar?.cgColor else { return .gray }
        return Color(cgColor: cgColor)
    }

    var displayTitle: String {
        let title = title ?? ""
        return title.isEmpty ? "新規予定" : title
    }
}

/// Wraps an event occurrence for `.sheet(item:)`.
struct EventRef: Identifiable {
    let id = UUID()
    let event: EKEvent
}

struct CalendarDot: View {
    let color: Color
    var size: CGFloat = 10

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

struct CheckMark: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.brand)
    }
}

/// While a finger is on this view, `locked` is true; pagers use it to stay put so the row gets the swipe.
/// `@GestureState` resets on its own even when the system cancels the touch.
private struct PagerLock: ViewModifier {
    @Binding var locked: Bool
    @GestureState private var touching = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).updating($touching) { _, state, _ in state = true }
            )
            .onChange(of: touching) { _, new in locked = new }
    }
}

extension View {
    func locksPager(_ locked: Binding<Bool>) -> some View {
        modifier(PagerLock(locked: locked))
    }
}

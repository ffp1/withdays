import EventKit
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

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

/// Touches that start on this view never page a horizontal pager around it (rows keep their swipe actions,
/// lists still scroll vertically). It works at the UIKit level: the pager's pan must wait for this
/// recognizer to fail, and it doesn't fail until the finger lifts.
private struct PagerBlocker: UIGestureRecognizerRepresentable {
    func makeUIGestureRecognizer(context: Context) -> TouchWatchRecognizer {
        let recognizer = TouchWatchRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: TouchWatchRecognizer, context: Context) {}

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        /// Only a horizontal pager's pan has to wait; vertical lists and swipe actions are untouched.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard let scrollView = other.view as? UIScrollView, other === scrollView.panGestureRecognizer else { return false }
            return scrollView.contentSize.width > scrollView.bounds.width + 1
                && scrollView.contentSize.height <= scrollView.bounds.height + 1
        }
    }
}

/// Recognizes on touch-down and ends on lift-off.
final class TouchWatchRecognizer: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .began
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }
}

extension View {
    func blocksPager() -> some View {
        gesture(PagerBlocker())
    }
}

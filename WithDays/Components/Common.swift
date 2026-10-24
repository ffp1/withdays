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

/// While a finger is on this view, `locked` is true; pagers use it to stay put so the row gets the swipe.
/// A SwiftUI drag gesture here would swallow the List's swipe actions, so this watches touches with a
/// UIKit recognizer that never blocks or delays anything else.
private struct PagerLock: ViewModifier {
    @Binding var locked: Bool

    func body(content: Content) -> some View {
        content.gesture(TouchWatcher { locked = $0 })
    }
}

private struct TouchWatcher: UIGestureRecognizerRepresentable {
    var onChange: (Bool) -> Void

    func makeUIGestureRecognizer(context: Context) -> TouchWatchRecognizer {
        let recognizer = TouchWatchRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: TouchWatchRecognizer, context: Context) {
        switch recognizer.state {
        case .began: onChange(true)
        case .ended, .cancelled, .failed: onChange(false)
        default: break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// Reports touch-down and lift-off only.
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
    func locksPager(_ locked: Binding<Bool>) -> some View {
        modifier(PagerLock(locked: locked))
    }
}

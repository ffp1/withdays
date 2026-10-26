import SwiftUI

/// One undo toast at a time, for any screen (calendar deletes / moves / duplicates, ToDo deletes).
/// It doesn't block the rest of the screen; it just goes away after a few seconds.
@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let undo: () -> Void
    }

    private(set) var current: Toast?

    func show(_ message: String, undo: @escaping () -> Void) {
        let toast = Toast(message: message, undo: undo)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.7)) { current = toast }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if current?.id == toast.id { dismiss() }
        }
    }

    func performUndo() {
        current?.undo()
        dismiss()
    }

    func dismiss() {
        withAnimation(.snappy(duration: 0.25)) { current = nil }
    }
}

/// The toast itself: grows up out of the bottom edge.
struct UndoToastView: View {
    let toast: ToastCenter.Toast
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(.system(size: 14, weight: .semibold))
            Button("元に戻す", action: onUndo)
                .font(.system(size: 14, weight: .bold))
                .underline()
                .foregroundStyle(Color.brand)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 16)
        .frame(height: 56)
        .glassEffect(.regular.interactive(), in: .capsule)
        .transition(
            .scale(scale: 0.3, anchor: .bottom)
                .combined(with: .offset(y: 24))
                .combined(with: .opacity)
        )
    }
}

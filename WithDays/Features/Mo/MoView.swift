import SwiftUI

enum MoTab {
    case stats, input, calendar
}

/// Mo: the household budget. Three tabs; holding the input tab goes back to the calendar.
struct MoView: View {
    var onCalendar: () -> Void

    @Environment(ToastCenter.self) private var toasts
    @State private var tab = MoTab.input
    /// The input tab's kind also colors the tab bar's center button, as on the web app.
    @State private var kind = MoKind.expense

    var body: some View {
        ZStack {
            switch tab {
            case .stats:
                MoStatsView()
                    .transition(.opacity)
            case .input:
                MoInputView(kind: $kind)
                    .transition(.opacity)
            case .calendar:
                MoCalendarView()
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: tab)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Typing a memo shows the keyboard over the screen instead of squeezing it.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if let toast = toasts.current {
                    UndoToastView(toast: toast) { toasts.performUndo() }
                        .padding(.horizontal, 20)
                        .id(toast.id)
                }
                MoTabBar(tab: $tab, color: kind.color, onCalendar: onCalendar)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

private struct MoTabBar: View {
    @Binding var tab: MoTab
    let color: Color
    var onCalendar: () -> Void

    @State private var leaving = false

    var body: some View {
        HStack(spacing: 0) {
            side(.stats, icon: "chart.pie.fill", label: "統計")
            Color.clear.frame(width: 96)
            side(.calendar, icon: "calendar", label: "カレンダー")
        }
        .frame(height: 64)
        .glassEffect(.regular, in: .capsule)
        .overlay {
            // The input tab stands out: a big raised button. Holding it goes back to the calendar.
            Image(systemName: "plus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
                .glassEffect(.regular.tint(color).interactive(), in: .circle)
                .scaleEffect(tab == .input ? 1 : 0.92)
                .offset(y: -18)
                .contentShape(Circle())
                .onTapGesture { tab = .input }
                .onLongPressGesture(minimumDuration: 0.5) {
                    leaving.toggle()
                    onCalendar()
                }
                .animation(.snappy, value: tab)
                .animation(.snappy, value: color)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .sensoryFeedback(.selection, trigger: tab)
        .sensoryFeedback(.impact(weight: .medium), trigger: leaving)
    }

    private func side(_ target: MoTab, icon: String, label: String) -> some View {
        Button { tab = target } label: {
            VStack(spacing: 2) {
                // The color shows the selection; the symbol bounces when picked.
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolEffect(.bounce, value: tab == target)
                Text(label)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(tab == target ? color : Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

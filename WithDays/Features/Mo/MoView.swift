import SwiftUI

enum MoTab {
    case stats, input, calendar
}

/// Mo: the household budget. Three tabs; double-tapping ＋ switches 支出 / 収入, holding it goes back to Cal.
struct MoView: View {
    var onCalendar: () -> Void

    @Environment(ToastCenter.self) private var toasts
    @State private var tab = MoTab.input
    /// The input tab's kind also colors the tab bar's center button, as on the web app.
    @State private var kind = MoKind.expense
    /// How far into holding ＋ (0–1): everything but ＋ dims and blurs on the way back to the calendar.
    @State private var press: CGFloat = 0

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
        .modifier(MoHoldDim(press: press))
        // Typing a memo shows the keyboard over the screen instead of squeezing it.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if let toast = toasts.current {
                    UndoToastView(toast: toast) { toasts.performUndo() }
                        .padding(.horizontal, 20)
                        .id(toast.id)
                        .modifier(MoHoldDim(press: press))
                }
                MoTabBar(tab: $tab, kind: $kind, press: $press, onCalendar: onCalendar)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

private struct MoTabBar: View {
    @Binding var tab: MoTab
    @Binding var kind: MoKind
    @Binding var press: CGFloat
    var onCalendar: () -> Void

    @State private var leaving = false
    @State private var lastTap = Date.distantPast

    private var color: Color { kind.color }

    var body: some View {
        HStack(spacing: 0) {
            side(.stats, icon: "chart.pie.fill", label: "統計")
            Color.clear.frame(width: 96)
            side(.calendar, icon: "calendar", label: "カレンダー")
        }
        .frame(height: 64)
        .glassEffect(.regular, in: .capsule)
        // The capsule's corners mustn't get a dark box, so it darkens itself instead.
        .blur(radius: 6 * press)
        .brightness(-0.08 * press)
        .overlay {
            // The input tab stands out: a big raised button. Holding it goes back to the calendar.
            Image(systemName: "plus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                // Turns into × as the hold goes on.
                .rotationEffect(.degrees(45 * Double(press)))
                .frame(width: 80, height: 80)
                .glassEffect(.regular.tint(color).interactive(), in: .circle)
                .scaleEffect(tab == .input ? 1 : 0.92)
                .offset(y: -18)
                .contentShape(Circle())
                // A second tap soon after switches 支出 / 収入; the first still opens input at once.
                .onTapGesture {
                    let now = Date()
                    if tab == .input, now.timeIntervalSince(lastTap) < 0.3 {
                        withAnimation(.snappy) { kind = kind == .expense ? .income : .expense }
                        lastTap = .distantPast
                    } else {
                        tab = .input
                        lastTap = now
                    }
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    leaving.toggle()
                    onCalendar()
                } onPressingChanged: { pressing in
                    withAnimation(pressing ? .easeIn(duration: 0.5) : .easeOut(duration: 0.2)) {
                        press = pressing ? 1 : 0
                    }
                }
                .animation(.snappy, value: tab)
                .animation(.snappy, value: color)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .sensoryFeedback(.selection, trigger: tab)
        .sensoryFeedback(.selection, trigger: kind)
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

/// Dims and blurs a view as ＋ is held, light enough that it stays just readable.
private struct MoHoldDim: ViewModifier {
    let press: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: 6 * press)
            .overlay {
                Color.black.opacity(0.12 * press)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
    }
}

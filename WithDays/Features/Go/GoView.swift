import SwiftUI

/// Go: the next target time of the selected preset and how long is left, centred on the screen.
/// Swipe up anywhere (or tap the target) for the presets. The navigation bar's button goes back to the calendar.
struct GoView: View {
    /// Also opened from the navigation bar's top-left button.
    @Binding var showPresets: Bool

    @Environment(GoStore.self) private var go

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            countdown(now: context.date)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                guard value.translation.height < -60, abs(value.translation.height) > abs(value.translation.width) else { return }
                showPresets = true
            }
        )
        .sheet(isPresented: $showPresets) {
            GoPresetSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: showPresets) { _, new in new }
        .task {
            // Temporary presets expire after a day, even while this screen stays open.
            while !Task.isCancelled {
                go.expireTemporary()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    @ViewBuilder
    private func countdown(now: Date) -> some View {
        if let preset = go.selectedPreset, let next = GoData.nextTarget(for: preset, now: now) {
            let seconds = max(0, Int(next.date.timeIntervalSince(now).rounded(.up)))
            VStack(spacing: 12) {
                // Target time: faint grey, as on the web.
                Text(next.time)
                    .font(.system(size: 27, weight: .regular))
                    .monospacedDigit()
                    .tracking(4)
                    .foregroundStyle(Self.targetGrey)
                    .contentTransition(.numericText())
                    .onTapGesture { showPresets = true }
                if seconds >= 3600 {
                    // An hour or more to go: a clock instead of the countdown, as on the web.
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 96, weight: .ultraLight))
                        .foregroundStyle(Self.goBlue)
                } else {
                    VStack(spacing: -17) {
                        remaining(seconds / 60, unit: "分")
                        remaining(seconds % 60, unit: "秒")
                    }
                }
            }
            .animation(.snappy, value: seconds)
            .animation(.snappy, value: next.time)
        } else {
            Text("プリセットがありません")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Self.targetGrey)
                .onTapGesture { showPresets = true }
        }
    }

    /// #27a and #aaa from the web app.
    private static let goBlue = Color(uiColor: UIColor(hex: 0x2277AA))
    private static let targetGrey = Color(uiColor: UIColor(hex: 0xAAAAAA))

    private func remaining(_ value: Int, unit: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            spacedDigits(String(format: "%02d", value), width: 76, size: 112, weight: .ultraLight, color: Self.goBlue)
            Text(unit)
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(Self.goBlue.opacity(0.67))
        }
    }

    /// Each character in a fixed-width slot, which spaces the digits like the web app and lets
    /// every digit roll on its own.
    private func spacedDigits(_ text: String, width: CGFloat, size: CGFloat, weight: Font.Weight, color: Color) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .font(.system(size: size, weight: weight))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText(countsDown: true))
                    .frame(width: character == ":" ? width * 0.3 : width)
            }
        }
    }
}

import SwiftUI

/// Go: the next target time of the selected preset and how long is left, centred on the screen.
/// Swipe up anywhere (or tap the target) for the presets. The top-right button goes back to the calendar.
struct GoView: View {
    var onClose: () -> Void

    @Environment(GoStore.self) private var go
    @State private var showPresets = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
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
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .padding(.trailing, 16)
            .padding(.top, 8)
        }
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
            VStack(spacing: 4) {
                Text(next.time)
                    .font(.system(size: 34, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .onTapGesture { showPresets = true }
                if seconds >= 3600 {
                    // An hour or more to go: a clock instead of the countdown, as on the web.
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 96, weight: .ultraLight))
                        .foregroundStyle(Color.brand)
                        .padding(.top, 12)
                } else {
                    remaining(seconds / 60, unit: "分")
                    remaining(seconds % 60, unit: "秒")
                }
            }
            .animation(.snappy, value: seconds)
            .animation(.snappy, value: next.time)
        } else {
            Text("プリセットがありません")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(.secondary)
                .onTapGesture { showPresets = true }
        }
    }

    private func remaining(_ value: Int, unit: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(String(format: "%02d", value))
                .font(.system(size: 132, weight: .thin))
                .monospacedDigit()
                .foregroundStyle(Color.brand)
                .contentTransition(.numericText(countsDown: true))
            Text(unit)
                .font(.system(size: 46, weight: .thin))
                .foregroundStyle(Color.brand.opacity(0.6))
        }
    }
}

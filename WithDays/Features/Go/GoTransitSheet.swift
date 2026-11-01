import SwiftUI

/// Holding ＋ in the presets: search a destination, and the next trains from the station near here
/// become a temporary preset named after the route.
struct GoTransitSheet: View {
    /// Called once the preset is made and selected.
    var onDone: () -> Void

    @Environment(GoStore.self) private var go
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.goTransitMargin) private var margin = 2

    @State private var query = ""
    @State private var places: [Transit.Place] = []
    @State private var planning: Transit.Place?
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("電車から作成")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.brand)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.brand)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            VStack(spacing: 6) {
                TextField("行き先を検索", text: $query)
                    .font(.system(size: 24, weight: .bold))
                    .focused($focused)
                    .submitLabel(.search)
                Rectangle()
                    .fill(Color.brand)
                    .frame(height: 2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            List(places) { place in
                Button { plan(to: place) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(.system(size: 16, weight: .semibold))
                        if let description = place.description {
                            Text(description)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)

            Text("現在地から最寄り駅を使い、\(margin)分後以降の電車を最大\(GoPreset.maxTimes)本入れます　経路データ: Transit API")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
        }
        .disabled(planning != nil)
        .overlay {
            if let planning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("\(planning.name)までの電車を検索中")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
        }
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                places = []
                return
            }
            // Wait for the typing (and the Japanese input) to settle.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            if let found = try? await Transit.suggest(text), !Task.isCancelled {
                places = found
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            focused = true
        }
        .errorAlert($errorMessage)
    }

    private func plan(to place: Transit.Place) {
        focused = false
        planning = place
        Task {
            defer { planning = nil }
            do {
                let here = try await Locator.current()
                let route = try await Transit.departures(
                    from: here,
                    to: place,
                    after: .now.addingTimeInterval(TimeInterval(margin * 60)),
                    limit: GoPreset.maxTimes
                )
                go.addTemporary(route: route.name, times: route.times)
                onDone()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

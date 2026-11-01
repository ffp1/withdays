import SwiftUI

/// Holding ＋ in the presets: search a station, pick one of the ways there (quickest first),
/// and its trains' departures become a temporary preset named after the route.
struct GoTransitSheet: View {
    /// Called once the preset is made and selected.
    var onDone: () -> Void

    @Environment(GoStore.self) private var go
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.goTransitMargin) private var margin = 2

    @State private var query = ""
    @State private var stations: [Transit.Place] = []
    /// The station picked, and the ways there once found.
    @State private var destination: Transit.Place?
    @State private var options: [Transit.Option] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if destination == nil {
                searchView
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                optionList
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            Text("経路データ: Transit API")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
        }
        .animation(.snappy, value: destination)
        .overlay {
            if loading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("経路を検索中")
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
                stations = []
                return
            }
            // Wait for the typing (and the Japanese input) to settle.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            if let found = try? await Transit.suggest(text), !Task.isCancelled {
                stations = found.filter { $0.kind == "station" }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            focused = true
        }
        .errorAlert($errorMessage)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if destination != nil {
                Button {
                    destination = nil
                    options = []
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.brand)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            Text(destination.map { "\($0.name)まで" } ?? "電車から作成")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.brand)
                .lineLimit(1)
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
    }

    private var searchView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                TextField("駅を検索", text: $query)
                    .font(.system(size: 24, weight: .bold))
                    .focused($focused)
                    .submitLabel(.search)
                Rectangle()
                    .fill(Color.brand)
                    .frame(height: 2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            List(stations) { station in
                Button { search(to: station) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(station.name)
                            .font(.system(size: 16, weight: .semibold))
                        if let description = station.description {
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
            .disabled(loading)
        }
    }

    /// Quickest first; each shows the departure of every train to take.
    private var optionList: some View {
        List(options) { option in
            Button {
                go.addTemporary(route: option.name, times: option.rides.map(\.time))
                onDone()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(option.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.brand)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 8)
                        Text("\(option.minutes)分")
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                    }
                    ForEach(Array(option.rides.enumerated()), id: \.offset) { _, ride in
                        HStack(spacing: 8) {
                            Text(ride.time)
                                .font(.system(size: 20, weight: .light))
                                .monospacedDigit()
                            Text(ride.line)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Text("\(option.arrival) 着")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    private func search(to station: Transit.Place) {
        focused = false
        loading = true
        Task {
            defer { loading = false }
            do {
                let here = try await Locator.current()
                let found = try await Transit.options(
                    from: here,
                    to: station,
                    after: .now.addingTimeInterval(TimeInterval(margin * 60)),
                    limit: 10
                )
                options = found
                destination = station
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

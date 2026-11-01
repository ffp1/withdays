import SwiftUI

/// Times first (up to ten, one per page), then the name. A preset saved without a name is temporary.
struct GoEditorView: View {
    let target: GoEditTarget

    @Environment(GoStore.self) private var go
    @Environment(\.dismiss) private var dismiss

    @State private var hours: [String]
    @State private var minutes: [String]
    @State private var page = 0
    @State private var showName = false
    @State private var name: String
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case hour(Int), minute(Int)
    }

    init(target: GoEditTarget) {
        self.target = target
        var times: [String]
        switch target {
        case .new:
            // One time, 30 minutes from now; the other pages start empty.
            let calendar = CalendarMath.calendar
            times = [30].map { offset in
                let date = Date.now.addingTimeInterval(TimeInterval(offset * 60))
                return GoData.format(hour: calendar.component(.hour, from: date), minute: calendar.component(.minute, from: date))
            }
            _name = State(initialValue: "")
        case .edit(let preset):
            times = preset.times
            _name = State(initialValue: preset.isTemporary ? "" : preset.name)
        }
        let parsed = times.prefix(GoPreset.maxTimes).map { $0.split(separator: ":").map(String.init) }
        let pad = Array(repeating: "", count: GoPreset.maxTimes - parsed.count)
        _hours = State(initialValue: parsed.map { $0.first ?? "" } + pad)
        _minutes = State(initialValue: parsed.map { $0.count > 1 ? $0[1] : "" } + pad)
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Text("No.\(page + 1)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.green)
                    .contentTransition(.numericText(value: Double(page)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    pageButton(-1, icon: "chevron.left")
                    TabView(selection: $page) {
                        ForEach(0..<GoPreset.maxTimes, id: \.self) { index in
                            slot(index).tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 150)
                    pageButton(1, icon: "chevron.right")
                }

                if let problem {
                    Text(problem)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }

                Spacer(minLength: 0)

                Button {
                    focus = nil
                    showName = true
                } label: {
                    Text("保存")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 140)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .disabled(problem != nil)
                .padding(.bottom, 20)
            }
            .animation(.snappy, value: page)
        }
        .onChange(of: focus) { _, new in
            guard new != nil else { return }
            DispatchQueue.main.async {
                UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            focus = .hour(0)
        }
        .sheet(isPresented: $showName) {
            GoNameSheet(name: $name, onSave: commit)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(isNew ? "新規プリセット" : displayTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.brand)
                .lineLimit(1)
            if isNew {
                Text("を追加")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.brand.opacity(0.7))
            }
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

    private var displayTitle: String {
        if case .edit(let preset) = target { return go.displayName(of: preset) }
        return ""
    }

    private func slot(_ index: Int) -> some View {
        HStack(spacing: 16) {
            timeField(hour: true, index)
            Text(":")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.secondary)
            timeField(hour: false, index)
        }
    }

    private func timeField(hour: Bool, _ index: Int) -> some View {
        VStack(spacing: 6) {
            TextField("00", text: binding(hour: hour, index))
                .font(.system(size: 72, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.brand)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .focused($focus, equals: hour ? .hour(index) : .minute(index))
                .frame(width: 120)
            Rectangle()
                .fill(Color.brand.opacity(0.3))
                .frame(width: 120, height: 2)
        }
    }

    private func pageButton(_ step: Int, icon: String) -> some View {
        let target = page + step
        return Button { page = target } label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 150)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity((0..<GoPreset.maxTimes).contains(target) ? 1 : 0)
        .disabled(!(0..<GoPreset.maxTimes).contains(target))
    }

    /// Digits only, two at most; complete hours move on to the minutes of the same time.
    private func binding(hour: Bool, _ index: Int) -> Binding<String> {
        Binding(
            get: { hour ? hours[index] : minutes[index] },
            set: { new in
                let digits = String(new.compactMap(\.wholeNumberValue).map(String.init).joined().prefix(2))
                let old = hour ? hours[index] : minutes[index]
                if hour { hours[index] = digits } else { minutes[index] = digits }
                // Only real typing moves on: focusing a field can write back its unchanged value,
                // and a full hour like "13" would otherwise skip straight to the minutes.
                guard digits != old, digits.count == 2, let value = Int(digits), value <= (hour ? 23 : 59) else { return }
                if hour { focus = .minute(index) }
            }
        )
    }

    /// Filled times must be complete, in range, ascending and without gaps; at least one is needed.
    private var problem: String? {
        let filled = (0..<GoPreset.maxTimes).filter { !hours[$0].isEmpty || !minutes[$0].isEmpty }
        guard let last = filled.last else { return "時刻を入力してください" }
        var previous = -1
        for index in 0...last {
            guard let hour = Int(hours[index]), let minute = Int(minutes[index]), hour <= 23, minute <= 59 else {
                return "時刻を途中で空けず、00〜23時・00〜59分で入力してください"
            }
            let value = hour * 60 + minute
            if value < previous { return "左の時刻以降を入力してください" }
            previous = value
        }
        return nil
    }

    private func commit() {
        let filled = (0..<GoPreset.maxTimes).filter { !hours[$0].isEmpty }
        let times = filled.compactMap { index -> String? in
            guard let hour = Int(hours[index]), let minute = Int(minutes[index]) else { return nil }
            return GoData.format(hour: hour, minute: minute)
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? GoPreset.temporaryName : trimmed
        switch target {
        case .new:
            go.save(GoPreset(id: GoData.newID(), name: finalName, times: times, createdAt: .now))
        case .edit(var preset):
            // A temporary preset that gets a name stops expiring; naming one temporary restarts its day.
            if preset.isTemporary != (finalName == GoPreset.temporaryName) { preset.createdAt = .now }
            preset.name = finalName
            preset.times = times
            go.save(preset)
        }
        dismiss()
    }
}

/// The second step: the preset's name. Left empty, the preset is temporary (24 hours).
private struct GoNameSheet: View {
    @Binding var name: String
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("プリセット名")
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

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                TextField("ex; 通勤時間", text: $name)
                    .font(.system(size: 34, weight: .bold))
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                Rectangle()
                    .fill(Color.brand)
                    .frame(height: 2)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 0)

            Button(action: save) {
                Text("保存")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 140)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .padding(.bottom, 20)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            focused = true
        }
    }

    /// The editor closes itself (and this sheet with it).
    private func save() {
        onSave()
    }
}

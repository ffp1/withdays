import SwiftUI

enum GoEditTarget: Identifiable {
    case new
    case edit(GoPreset)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let preset): preset.id
        }
    }
}

/// The presets: tap to use one, swipe left to delete (with undo), swipe right to edit, ＋ to add.
struct GoPresetSheet: View {
    @Environment(GoStore.self) private var go
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var editing: GoEditTarget?

    var body: some View {
        NavigationStack {
            List {
                ForEach(go.presets) { preset in
                    Button {
                        go.select(preset.id)
                        dismiss()
                    } label: {
                        row(preset)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(rowBackground(selected: preset.id == go.state.selected))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(preset) } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                    }
                    .swipeActions(edge: .leading) {
                        Button { editing = .edit(preset) } label: {
                            Image(systemName: "pencil.and.outline")
                        }
                        .tint(.brand)
                    }
                }
            }
            .listStyle(.plain)
            .contentMargins(.bottom, 96, for: .scrollContent)
            .overlay {
                if go.presets.isEmpty {
                    Text("プリセットがありません")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .overlay(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 10) {
                    // The undo toast shows here too, since this sheet covers the main one.
                    if let toast = toasts.current {
                        UndoToastView(toast: toast) { toasts.performUndo() }
                            .id(toast.id)
                    }
                    Spacer(minLength: 0)
                    Button { editing = .new } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 26.4, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                }
                .padding(20)
            }
        }
        .sheet(item: $editing) { target in
            GoEditorView(target: target)
        }
    }

    private func row(_ preset: GoPreset) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(go.displayName(of: preset))
                .font(.system(size: 15, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.brand)
            HStack(spacing: 10) {
                ForEach(Array(preset.times.enumerated()), id: \.offset) { index, time in
                    if index > 0 {
                        Text("-").foregroundStyle(.tertiary)
                    }
                    Text(time)
                        .monospacedDigit()
                }
            }
            .font(.system(size: 22, weight: .light))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The preset in use gets a bar on its left edge.
    private func rowBackground(selected: Bool) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(selected ? Color.brand : Color.clear)
                .frame(width: 4)
            Spacer(minLength: 0)
        }
    }

    private func delete(_ preset: GoPreset) {
        guard let removed = go.delete(preset.id) else { return }
        toasts.show("プリセットを削除しました") {
            go.restore(removed.preset, at: removed.index, select: removed.wasSelected)
        }
    }
}

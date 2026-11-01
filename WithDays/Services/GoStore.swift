import SwiftUI

/// Go presets for the app; saved through `GoData` shared through the App Group.
@MainActor
@Observable
final class GoStore {
    private(set) var state = GoData.load()

    var presets: [GoPreset] { GoData.ordered(state.presets) }

    var selectedPreset: GoPreset? { GoData.selectedPreset(in: state) }

    /// Names as listed: TEMPORARY for the temporary preset, and a number after repeated names.
    func displayName(of preset: GoPreset) -> String {
        let base = preset.isTemporary ? "TEMPORARY" : preset.name
        let same = presets.filter { $0.name == preset.name }
        guard let index = same.firstIndex(where: { $0.id == preset.id }), index > 0 else { return base }
        return "\(base) \(index + 1)"
    }

    func select(_ id: String) {
        state.selected = id
        persist()
    }

    /// Adds a new preset (selecting it if nothing is selected) or replaces an existing one.
    func save(_ preset: GoPreset) {
        if let index = state.presets.firstIndex(where: { $0.id == preset.id }) {
            state.presets[index] = preset
        } else {
            state.presets.append(preset)
            if state.selected == nil { state.selected = preset.id }
        }
        persist()
    }

    /// Removes a preset; returns what undo needs to put it back.
    func delete(_ id: String) -> (preset: GoPreset, index: Int, wasSelected: Bool)? {
        guard let index = state.presets.firstIndex(where: { $0.id == id }) else { return nil }
        let preset = state.presets.remove(at: index)
        let wasSelected = state.selected == id
        if wasSelected { state.selected = presets.first?.id }
        persist()
        return (preset, index, wasSelected)
    }

    func restore(_ preset: GoPreset, at index: Int, select: Bool) {
        state.presets.insert(preset, at: min(index, state.presets.count))
        if select || state.selected == nil { state.selected = preset.id }
        persist()
    }

    func expireTemporary() {
        if GoData.expireTemporary(&state) { persist() }
    }

    private func persist() {
        GoData.save(state)
    }
}

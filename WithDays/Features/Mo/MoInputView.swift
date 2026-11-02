import SwiftUI

/// Enter an amount on the keypad, then tap a category to record it (now).
/// Holding a category edits them: tap to edit, × to delete, drag to reorder.
struct MoInputView: View {
    @Binding var kind: MoKind

    @Environment(MoStore.self) private var mo
    @Environment(ToastCenter.self) private var toasts
    @State private var digits = ""
    @State private var memo = ""
    @State private var editing = false
    @State private var categorySheet: MoCategorySheet.Target?
    @State private var shake = 0
    @State private var saved = 0
    @FocusState private var memoFocused: Bool

    private static let maxDigits = 8

    var body: some View {
        VStack(spacing: 0) {
            kindPicker
                .padding(.top, 12)

            amountView
                .padding(.top, 16)

            categoryStrip
                .padding(.top, 14)

            memoField
                .padding(.horizontal, 20)
                .padding(.top, 10)

            MoKeypad(onDigit: type, onDelete: deleteLast, onClear: { digits = "" })
                .padding(.horizontal, 12)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            memoFocused = false
            if editing { withAnimation(.snappy) { editing = false } }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.error, trigger: shake)
        .sheet(item: $categorySheet) { target in
            MoCategorySheet(target: target, kind: kind)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Parts

    private var kindPicker: some View {
        HStack(spacing: 10) {
            ForEach(MoKind.allCases, id: \.self) { item in
                Button {
                    withAnimation(.snappy) {
                        kind = item
                        editing = false
                    }
                } label: {
                    Label(item.label, systemImage: item == .expense ? "arrow.up" : "arrow.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(kind == item ? Color.white : item.color)
                        .padding(.horizontal, 18)
                        .frame(height: 38)
                        .background(Capsule().fill(kind == item ? item.color : item.color.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .trailing) {
            if editing {
                Button("完了") { withAnimation(.snappy) { editing = false } }
                    .font(.system(size: 15, weight: .bold))
                    .buttonStyle(.glass)
                    .offset(x: 90)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var amountView: some View {
        VStack(spacing: 0) {
            Text(digits.isEmpty ? "-" : MoFormat.amount(Int(digits) ?? 0))
                .font(MoFormat.number(72))
                .monospacedDigit()
                .foregroundStyle(kind.color)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: digits)
                .keyframeAnimator(initialValue: 0.0, trigger: shake) { content, x in
                    content.offset(x: x)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(-10, duration: 0.05)
                        LinearKeyframe(10, duration: 0.05)
                        LinearKeyframe(-6, duration: 0.05)
                        LinearKeyframe(6, duration: 0.05)
                        LinearKeyframe(0, duration: 0.05)
                    }
                }
                .frame(height: 80)
                .padding(.horizontal, 24)
            Text(digits.isEmpty ? "金額を入力" : "カテゴリを選択")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
    }

    private var categoryStrip: some View {
        let categories = mo.categories(kind)
        let enabled = !digits.isEmpty || editing
        return ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(categories) { category in
                    MoCategoryTile(
                        category: category,
                        kind: kind,
                        enabled: enabled,
                        editing: editing,
                        onTap: { tap(category) },
                        onLongPress: {
                            memoFocused = false
                            withAnimation(.snappy) { editing = true }
                        },
                        onDelete: { delete(category) },
                        onMove: { label in
                            guard let dragged = categories.first(where: { $0.label == label }) else { return }
                            withAnimation(.snappy) { mo.moveCategory(dragged, to: category, kind: kind) }
                        }
                    )
                }
                Button {
                    withAnimation(.snappy) { editing = false }
                    categorySheet = .new
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 60, height: 60)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])))
                        Text("カテゴリ追加")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 72)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .animation(.snappy, value: categories)
    }

    private var memoField: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .foregroundStyle(.secondary)
            TextField("任意のメモを入力…", text: $memo)
                .font(.system(size: 15))
                .focused($memoFocused)
                .submitLabel(.done)
            if !memo.isEmpty {
                Button { memo = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemFill)))
        .animation(.snappy, value: memo.isEmpty)
    }

    // MARK: Actions

    private func type(_ key: String) {
        let next = digits + key
        guard next.count <= Self.maxDigits else {
            shake += 1
            return
        }
        // No leading zeros: "0" then "5" is just 5.
        digits = Int(next).map { $0 == 0 ? "" : String($0) } ?? digits
    }

    private func deleteLast() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
    }

    private func tap(_ category: MoCategory) {
        if editing {
            categorySheet = .edit(category)
            return
        }
        guard let amount = Int(digits), amount > 0 else { return }
        let record = mo.add(amount: amount, kind: kind, category: category, memo: memo.trimmingCharacters(in: .whitespacesAndNewlines))
        digits = ""
        memo = ""
        memoFocused = false
        saved += 1
        toasts.show("\(category.label)：¥\(MoFormat.amount(amount))") {
            _ = mo.delete(record.id)
        }
    }

    private func delete(_ category: MoCategory) {
        let current = kind
        guard let index = mo.deleteCategory(category, kind: current) else { return }
        toasts.show("「\(category.label)」を削除しました") {
            mo.restoreCategory(category, at: index, kind: current)
        }
    }
}

/// One category: icon tile and name. Disabled until an amount is entered; wiggles while editing.
private struct MoCategoryTile: View {
    let category: MoCategory
    let kind: MoKind
    let enabled: Bool
    let editing: Bool
    var onTap: () -> Void
    var onLongPress: () -> Void
    var onDelete: () -> Void
    var onMove: (String) -> Void

    @State private var targeted = false

    var body: some View {
        let tile = VStack(spacing: 6) {
            MoIcon(name: category.icon, size: 28)
                .foregroundStyle(kind.color)
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(kind.color.opacity(targeted ? 0.25 : 0.1)))
            Text(category.label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(width: 72)
        .overlay(alignment: .topTrailing) {
            if editing {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color(.darkGray)))
                }
                .buttonStyle(.plain)
                .offset(x: -2, y: -6)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .opacity(enabled ? 1 : 0.35)
        .modifier(Wiggle(active: editing))
        .contentShape(Rectangle())
        .onTapGesture { if enabled { onTap() } }
        .onLongPressGesture(minimumDuration: 0.5) { if !editing { onLongPress() } }

        if editing {
            // While editing, hold and drag a tile onto another to move it there.
            tile
                .draggable(category.label) {
                    MoIcon(name: category.icon, size: 28)
                        .foregroundStyle(kind.color)
                        .frame(width: 60, height: 60)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(kind.color.opacity(0.15)))
                }
                .dropDestination(for: String.self) { labels, _ in
                    guard let label = labels.first, label != category.label else { return false }
                    onMove(label)
                    return true
                } isTargeted: { targeted = $0 }
        } else {
            tile
        }
    }
}

/// The editing jiggle; only animates while active.
private struct Wiggle: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.phaseAnimator([-2.0, 2.0]) { view, angle in
                view.rotationEffect(.degrees(angle))
            } animation: { _ in .easeInOut(duration: 0.12) }
        } else {
            content
        }
    }
}

/// 1–9, 00, 0 and delete in a grid. Holding delete clears everything.
private struct MoKeypad: View {
    var onDigit: (String) -> Void
    var onDelete: () -> Void
    var onClear: () -> Void

    @State private var tick = 0

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "00", "0", "delete"]

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<4, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        key(keys[row * 3 + column])
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: tick)
    }

    @ViewBuilder
    private func key(_ key: String) -> some View {
        Button {
            tick += 1
            if key == "delete" { onDelete() } else { onDigit(key) }
        } label: {
            Group {
                if key == "delete" {
                    Image(systemName: "delete.left")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.moExpense.opacity(0.75))
                } else {
                    Text(key)
                        .font(MoFormat.number(34))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(MoKeyStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                guard key == "delete" else { return }
                tick += 1
                onClear()
            }
        )
    }
}

/// Keys grow while pressed, as on the web app.
private struct MoKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.45 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

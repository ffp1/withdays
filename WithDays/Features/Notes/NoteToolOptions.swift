import SwiftUI

extension Color {
    init(notesHex hex: Int) {
        self.init(uiColor: UIColor(notesHex: hex))
    }
}

/// The options of the tool in use: its colors, its width, and what else it can be set to.
/// Presets are applied with a tap; holding one saves the current value into it.
struct NoteToolOptions: View {
    let tool: NoteTool
    @Binding var settings: NoteToolSettings

    @State private var showFonts = false

    var body: some View {
        VStack(spacing: 12) {
            switch tool {
            case .pen:
                NoteColorOptions(color: $settings.pen.color, presets: $settings.pen.colors)
                NoteWidthOptions(width: $settings.pen.width, presets: $settings.pen.widths, range: 0.1...20, dot: { 2 + $0 * 1.25 })
            case .marker:
                NoteColorOptions(color: $settings.marker.color, presets: $settings.marker.colors)
                NoteWidthOptions(width: $settings.marker.width, presets: $settings.marker.widths, range: 4...50, dot: { 4 + $0 * 0.45 })
            case .tape:
                NoteColorOptions(color: $settings.tape.color, presets: $settings.tape.colors)
                NoteWidthOptions(width: $settings.tape.width, presets: $settings.tape.widths, range: 8...60, dot: { 4 + $0 * 0.4 })
            case .text:
                NoteColorOptions(color: $settings.text.color, presets: $settings.text.colors)
                NoteWidthOptions(width: $settings.text.width, presets: $settings.text.widths, range: 8...72, dot: { 6 + $0 * 0.3 })
                textExtras
            case .eraser:
                Picker("消し方", selection: $settings.eraserWhole) {
                    Text("線ごと").tag(true)
                    Text("なぞった所だけ").tag(false)
                }
                .pickerStyle(.segmented)
                if !settings.eraserWhole {
                    NoteWidthOptions(width: $settings.eraserWidth, presets: $settings.eraserWidths, range: 4...100, dot: { 4 + $0 * 0.25 })
                }
            case .select:
                EmptyView()
            }
            if tool != .select, tool != .eraser || !settings.eraserWhole {
                Text("プリセットは長押しで今の値を保存")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: 330)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    /// The font, bold, and a fill behind the text.
    @ViewBuilder
    private var textExtras: some View {
        Button { showFonts = true } label: {
            HStack(spacing: 6) {
                Text(NoteFont.name(settings.textFont))
                    .font(Font(NoteFont.font(settings.textFont, size: 15, bold: false) as CTFont))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showFonts) {
            NoteFontSheet(selection: $settings.textFont)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        HStack(spacing: 10) {
            Button { settings.textBold.toggle() } label: {
                Image(systemName: "bold")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(settings.textBold ? Color.white : Color.primary)
                    .frame(width: 44, height: 32)
                    .background(Capsule().fill(settings.textBold ? Color.brand : Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("背景")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
            Toggle("背景", isOn: Binding(
                get: { settings.textBackground != nil },
                set: { settings.textBackground = $0 ? (settings.textBackground ?? 0xFFE066) : nil }
            ))
            .labelsHidden()
            if let background = settings.textBackground {
                ColorPicker("背景の色", selection: Binding(
                    get: { Color(notesHex: background) },
                    set: { settings.textBackground = UIColor($0).notesHex }
                ), supportsOpacity: false)
                .labelsHidden()
            }
        }
    }
}

/// Ten color presets, then the system picker for any color at all.
struct NoteColorOptions: View {
    @Binding var color: Int
    @Binding var presets: [Int]

    @State private var saved = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(presets.indices, id: \.self) { index in
                Circle()
                    .fill(Color(notesHex: presets[index]))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                    .padding(3)
                    .overlay {
                        if presets[index] == color { Circle().strokeBorder(Color.brand, lineWidth: 2) }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .contentShape(Rectangle())
                    .onTapGesture { color = presets[index] }
                    .onLongPressGesture(minimumDuration: 0.45) {
                        presets[index] = color
                        saved += 1
                    }
            }
            ColorPicker("色を作る", selection: Binding(
                get: { Color(notesHex: color) },
                set: { color = UIColor($0).notesHex }
            ), supportsOpacity: false)
            .labelsHidden()
            .padding(.leading, 6)
        }
        .sensoryFeedback(.success, trigger: saved)
    }
}

/// A slider for any width, and four presets.
struct NoteWidthOptions: View {
    @Binding var width: Double
    @Binding var presets: [Double]
    let range: ClosedRange<Double>
    /// How big a dot shows this width.
    let dot: (Double) -> Double

    @State private var saved = 0

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.primary)
                    .frame(width: dot(width), height: dot(width))
                    .frame(width: 34, height: 34)
                Slider(value: $width, in: range)
                Text(width.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            HStack(spacing: 8) {
                ForEach(presets.indices, id: \.self) { index in
                    let selected = abs(presets[index] - width) < 0.05
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: min(dot(presets[index]), 22), height: min(dot(presets[index]), 22))
                        Text(presets[index].formatted(.number.precision(.fractionLength(0...1))))
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(Capsule().fill(selected ? Color.brand.opacity(0.18) : Color.primary.opacity(0.06)))
                    .contentShape(Rectangle())
                    .onTapGesture { width = presets[index] }
                    .onLongPressGesture(minimumDuration: 0.45) {
                        presets[index] = (width * 10).rounded() / 10
                        saved += 1
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: saved)
    }
}

/// What can be done with the selection. The short menu has cut, duplicate, delete and colors;
/// ⋯ opens the rest: to the front / to the back, and reading handwriting as text.
/// With nothing selected it offers to paste what was cut.
struct NoteSelectionOptions: View {
    let controller: NoteCanvasController
    let colors: [Int]
    var onToText: () -> Void

    @State private var detail = false
    @State private var custom = Color.black

    var body: some View {
        VStack(spacing: 10) {
            if controller.hasSelection {
                HStack(spacing: 8) {
                    action("カット", "scissors") { controller.perform(.cut) }
                    action("複製", "plus.square.on.square") { controller.perform(.duplicate) }
                    action("削除", "trash") { controller.perform(.delete) }
                    Button { detail.toggle() } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(detail ? Color.white : Color.primary)
                            .frame(width: 40, height: 40)
                            .background(Capsule().fill(detail ? Color.brand : Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 0) {
                    ForEach(colors, id: \.self) { hex in
                        Circle()
                            .fill(Color(notesHex: hex))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .contentShape(Rectangle())
                            .onTapGesture { controller.perform(.color(hex)) }
                    }
                    ColorPicker("色を作る", selection: Binding(
                        get: { custom },
                        set: {
                            custom = $0
                            controller.perform(.color(UIColor($0).notesHex))
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .padding(.leading, 6)
                }
                if detail {
                    HStack(spacing: 8) {
                        action("最上部へ", "square.3.layers.3d.top.filled") { controller.perform(.front) }
                        action("最下部へ", "square.3.layers.3d.bottom.filled") { controller.perform(.back) }
                    }
                    if controller.hasSelectedStrokes {
                        action("テキストに変換", "text.viewfinder", perform: onToText)
                    }
                }
            } else if controller.canPaste {
                action("ペースト", "doc.on.clipboard") { controller.paste() }
            }
        }
        .padding(14)
        .frame(maxWidth: 330)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .animation(.snappy(duration: 0.2), value: detail)
    }

    private func action(_ title: String, _ icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The fonts for text boxes: the picked ones first, then every family on the iPhone, each shown in itself.
struct NoteFontSheet: View {
    @Binding var selection: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("おすすめ") {
                ForEach(NoteFont.curated) { choice in
                    row(choice.font, choice.name)
                }
            }
            Section("すべてのフォント") {
                ForEach(NoteFont.all, id: \.self) { family in
                    row(family, family)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ font: String?, _ name: String) -> some View {
        Button {
            selection = font
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("あア亜 Abc 123")
                        .font(Font(NoteFont.font(font, size: 18, bold: false) as CTFont))
                        .foregroundStyle(.primary)
                    Text(name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selection == font {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.brand)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

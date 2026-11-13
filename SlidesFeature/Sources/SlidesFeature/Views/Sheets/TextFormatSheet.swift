import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// テキスト: font, size, style, alignment, color and spacing. While typing it formats the selected text;
/// otherwise the whole box.
struct TextFormatSheet: View {
    let formatter: TextFormatter
    var showsClose = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextFormatForm(formatter: formatter)
                .navigationTitle("テキスト")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if showsClose {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { dismiss() } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("閉じる")
                        }
                    }
                }
        }
    }
}

struct TextFormatForm: View {
    let formatter: TextFormatter

    var body: some View {
        let run = formatter.run
        let text = formatter.text
        Form {
            Section("フォント") {
                NavigationLink {
                    FontPickerView(formatter: formatter)
                } label: {
                    Text(FontLibrary.shared.label(for: run.font))
                        .font(Font(RichTextConverter.font(name: run.font, size: 17, bold: false, italic: false) as CTFont))
                }
            }
            Section("サイズ") {
                HStack {
                    Stepper(value: Binding(get: { run.size }, set: { size in formatter.applyRun(key: "size") { $0.size = size } }), in: 8...400, step: 1) {
                        Text("\(Int(run.size.rounded())) pt")
                            .monospacedDigit()
                    }
                }
                Slider(value: Binding(get: { run.size }, set: { size in formatter.applyRun(key: "size") { $0.size = size.rounded() } }), in: 8...400)
                    .tint(SlidesTheme.brand)
            }
            Section("スタイル") {
                HStack(spacing: 8) {
                    styleToggle("bold", "太字", run.bold) { $0.bold.toggle() }
                    styleToggle("italic", "斜体", run.italic) { $0.italic.toggle() }
                    styleToggle("underline", "下線", run.underline) { $0.underline.toggle() }
                    styleToggle("strikethrough", "取り消し線", run.strike) { $0.strike.toggle() }
                }
            }
            Section("配置") {
                Picker("横", selection: Binding(get: { text.hAlign }, set: { align in formatter.applyBox(key: "hAlign") { $0.hAlign = align } })) {
                    ForEach(HAlign.allCases, id: \.self) { align in
                        Image(systemName: align.icon).tag(align).accessibilityLabel(align.label)
                    }
                }
                .pickerStyle(.segmented)
                Picker("縦", selection: Binding(get: { text.vAlign }, set: { align in formatter.applyBox(key: "vAlign") { $0.vAlign = align } })) {
                    ForEach(VAlign.allCases, id: \.self) { align in
                        Text(align.label).tag(align)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("文字色") {
                ColorRow(color: run.color) { color in formatter.applyRun(key: "color") { $0.color = color } }
            }
            Section("効果") {
                Toggle("縁取り", isOn: Binding(get: { text.outline != nil }, set: { on in
                    formatter.applyBox(key: "outlineOn") { $0.outline = on ? ($0.outline ?? Stroke(color: .white, width: 4)) : nil }
                }))
                .tint(SlidesTheme.brand)
                if let outline = text.outline {
                    ColorRow(color: outline.color) { color in formatter.applyBox(key: "outlineColor") { $0.outline?.color = color } }
                    ValueSlider(
                        title: "縁取りの太さ",
                        value: Binding(get: { outline.width }, set: { value in formatter.applyBox(key: "outlineWidth") { $0.outline?.width = value } }),
                        range: 1...30
                    )
                }
                Toggle("影", isOn: Binding(get: { text.shadow != nil }, set: { on in
                    formatter.applyBox(key: "shadowOn") { $0.shadow = on ? ($0.shadow ?? ShadowStyle(blur: 12, x: 0, y: 6)) : nil }
                }))
                .tint(SlidesTheme.brand)
                if let shadow = text.shadow {
                    ColorRow(color: shadow.color) { color in formatter.applyBox(key: "shadowColor") { $0.shadow?.color = color } }
                    ValueSlider(title: "ぼかし", value: Binding(get: { shadow.blur }, set: { value in formatter.applyBox(key: "shadowBlur") { $0.shadow?.blur = value } }), range: 0...60)
                    ValueSlider(title: "横のずれ", value: Binding(get: { shadow.x }, set: { value in formatter.applyBox(key: "shadowX") { $0.shadow?.x = value } }), range: -40...40)
                    ValueSlider(title: "縦のずれ", value: Binding(get: { shadow.y }, set: { value in formatter.applyBox(key: "shadowY") { $0.shadow?.y = value } }), range: -40...40)
                }
            }
            Section("間隔") {
                ValueSlider(
                    title: "行間",
                    value: Binding(get: { text.lineSpacing }, set: { value in formatter.applyBox(key: "line") { $0.lineSpacing = value } }),
                    range: 0.6...3, step: 0.05, format: { String(format: "%.2f", $0) }
                )
                ValueSlider(
                    title: "字間",
                    value: Binding(get: { text.charSpacing }, set: { value in formatter.applyBox(key: "char") { $0.charSpacing = value } }),
                    range: -10...60, step: 1, format: { "\(Int($0.rounded())) pt" }
                )
            }
        }
    }

    private func styleToggle(_ icon: String, _ label: String, _ on: Bool, _ change: @escaping (inout TextRun) -> Void) -> some View {
        Button {
            formatter.applyRun(key: "style-\(icon)", change)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(on ? SlidesTheme.onBrand : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Capsule().fill(on ? SlidesTheme.brand : Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// フォント: imported fonts (swipe to delete) and system fonts, each shown in itself.
struct FontPickerView: View {
    let formatter: TextFormatter

    @Environment(\.modelContext) private var context
    @State private var library = FontLibrary.shared
    @State private var importing = false
    @State private var errorMessage: String?
    @State private var deletingFamily: [FontLibrary.ImportedFont]?

    var body: some View {
        let current = formatter.run.font
        List {
            Section {
                Button {
                    importing = true
                } label: {
                    Label("フォントを読み込む（.ttf / .otf）", systemImage: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 34)
                }
                .brandGlass()
                .listRowBackground(Color.clear)
            }
            if !library.imported.isEmpty {
                Section("読み込んだフォント") {
                    ForEach(library.importedFamilies, id: \.family) { group in
                        familyRow(
                            group.family, label: group.faces.first?.displayName ?? group.family,
                            faces: group.faces.map(\.postScriptName), tag: group.faces.first?.ext.uppercased(), current: current
                        )
                        .swipeActions(edge: .trailing) {
                            Button("削除", role: .destructive) { askToDelete(group.faces) }
                                .tint(.red)
                        }
                    }
                }
            }
            Section("システムフォント") {
                ForEach(FontLibrary.systemFamilies, id: \.family) { family in
                    familyRow(family.family, label: family.label, faces: FontFaces.faces(of: family.family), tag: nil, current: current)
                }
            }
        }
        .navigationTitle("フォント")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.fontTypes) { result in
            do {
                let font = try library.importFont(from: try result.get())
                formatter.applyRun(key: "font") { $0.font = font.postScriptName }
            } catch {
                errorMessage = (error as? FontLibrary.Failure)?.message ?? "フォントを読み込めませんでした。"
            }
        }
        .alert("エラー", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            "「\(deletingFamily?.first?.displayName ?? "")」を削除",
            isPresented: Binding(get: { deletingFamily != nil }, set: { if !$0 { deletingFamily = nil } }),
            presenting: deletingFamily
        ) { faces in
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) { faces.forEach(library.delete) }
        } message: { _ in
            Text("このフォントを使っているスライドがあります。削除すると標準のフォントで表示されます（もう一度読み込むと元に戻ります）。")
        }
    }

    private static let fontTypes: [UTType] = [
        UTType("public.truetype-ttf-font"), UTType("public.opentype-font"), UTType(filenameExtension: "ttf"), UTType(filenameExtension: "otf"),
    ].compactMap { $0 }

    /// A family with one face is picked here; one with several (weights) opens them.
    @ViewBuilder
    private func familyRow(_ family: String, label: String, faces: [String], tag: String?, current: String) -> some View {
        let regular = faces.first { FontFaces.faceLabel($0).contains("W3") || FontFaces.faceLabel($0) == "Regular" } ?? faces.first ?? family
        let chosen = FontFaces.family(of: current) == family
        if faces.count > 1 {
            NavigationLink {
                List(faces, id: \.self) { face in
                    row(face, FontFaces.faceLabel(face), tag: nil, current: current)
                }
                .navigationTitle(label)
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack {
                    Text(label)
                        .font(Font(RichTextConverter.font(name: regular, size: 18, bold: false, italic: false) as CTFont))
                    if let tag { tagView(tag) }
                    Spacer()
                    if chosen {
                        Text(FontFaces.faceLabel(current))
                            .font(.system(size: 13))
                            .foregroundStyle(SlidesTheme.brandText)
                    }
                }
            }
        } else {
            row(faces.first ?? family, label, tag: tag, current: current)
        }
    }

    private func tagView(_ tag: String) -> some View {
        Text(tag)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    private func row(_ name: String, _ label: String, tag: String?, current: String) -> some View {
        Button {
            formatter.applyRun(key: "font") { $0.font = name }
        } label: {
            HStack {
                Text(label)
                    .font(Font(RichTextConverter.font(name: name, size: 18, bold: false, italic: false) as CTFont))
                    .foregroundStyle(.primary)
                if let tag {
                    Text(tag)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                Spacer()
                if name == current {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(SlidesTheme.brandText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Deletes at once when no slide uses the family's fonts; otherwise asks first.
    private func askToDelete(_ faces: [FontLibrary.ImportedFont]) {
        let names = Set(faces.map(\.postScriptName))
        var used = formatter.editor.slides.contains { !$0.fontNames.isDisjoint(with: names) }
        if !used {
            let pages = (try? context.fetch(FetchDescriptor<SlidePage>())) ?? []
            used = pages.contains { page in
                !(SlideContent.decode(page.data)?.fontNames.isDisjoint(with: names) ?? true)
            }
        }
        if used {
            deletingFamily = faces
        } else {
            faces.forEach(library.delete)
        }
    }
}

/// 色: the text's color.
struct TextColorSheet: View {
    let formatter: TextFormatter

    var body: some View {
        NavigationStack {
            Form {
                Section("文字色") {
                    ColorRow(color: formatter.run.color) { color in formatter.applyRun(key: "color") { $0.color = color } }
                }
            }
            .navigationTitle("色")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

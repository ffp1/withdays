import PencilKit
import PhotosUI
import SwiftUI

enum NoteTool: String {
    case pen, marker, eraser, lasso

    var icon: String {
        switch self {
        case .pen: "pencil.tip"
        case .marker: "highlighter"
        case .eraser: "eraser"
        case .lasso: "lasso"
        }
    }
}

/// A file handed to the share sheet.
struct NoteShare: Identifiable {
    let url: URL
    var id: URL { url }
}

/// A note open for writing: one page at a time, turned with a two-finger swipe or the page buttons.
struct NoteEditorView: View {
    let noteID: String

    @Environment(NotesStore.self) private var notes
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    /// Which way the last turn went, for the slide.
    @State private var forward = true
    @State private var controller = NoteCanvasController()
    @State private var tool = NoteTool.pen
    @State private var showOptions = false
    @AppStorage(SettingsKey.notesPenColor) private var penColor = 0x1C1C1E
    @AppStorage(SettingsKey.notesPenWidth) private var penWidth = 3.0
    @AppStorage(SettingsKey.notesMarkerColor) private var markerColor = 0xFFD60A
    @AppStorage(SettingsKey.notesMarkerWidth) private var markerWidth = 16.0
    /// The eraser removes whole strokes, or only what it touches.
    @AppStorage(SettingsKey.notesEraserWhole) private var eraserWhole = true

    @State private var renaming = false
    @State private var name = ""
    @State private var confirmDelete = false
    @State private var showPhotos = false
    @State private var photo: PhotosPickerItem?
    @State private var share: NoteShare?
    @State private var errorMessage: String?

    static let colors = [0x1C1C1E, 0x8E8E93, 0xD12F2F, 0xF08C00, 0xFFD60A, 0x2FA84F, 0x1F7AE0, 0x7A4FD6, 0xE85D9E, 0x8B5A2B]
    private static let penWidths = [1.5, 3.0, 5.0, 8.0]
    private static let markerWidths = [10.0, 16.0, 24.0, 34.0]

    var body: some View {
        if let note = notes.note(noteID) {
            content(note)
        } else {
            // Deleted from under the editor.
            Color.clear.onAppear { dismiss() }
        }
    }

    private func content(_ note: Note) -> some View {
        let current = min(index, note.pages.count - 1)
        let page = note.pages[current]
        return VStack(spacing: 0) {
            topBar(note, page)
            ZStack {
                Color(uiColor: .systemGray5)
                NoteCanvas(
                    page: page,
                    pdf: notes.pdfPage(for: page, in: note),
                    image: notes.image(for: page, in: note),
                    tool: pkTool,
                    toolKey: toolKey,
                    controller: controller,
                    load: { notes.drawing(noteID, page.id) },
                    save: { notes.saveDrawing($0, noteID, page.id) },
                    onTurn: { turn($0, in: note) }
                )
                .id(page.id)
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading),
                    removal: .move(edge: forward ? .leading : .trailing)
                ))
            }
            .clipped()
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .bottom) { bottomBar(note, current) }
        .background(Color(uiColor: .systemBackground))
        .sensoryFeedback(.selection, trigger: tool)
        .sensoryFeedback(.impact(weight: .light), trigger: page.id)
        .alert("ノートの名前", isPresented: $renaming) {
            TextField("名前", text: $name)
            Button("キャンセル", role: .cancel) {}
            Button("OK") {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { notes.rename(noteID, to: trimmed) }
            }
        }
        .confirmationDialog("このページを削除します", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                forward = false
                withAnimation(.snappy) {
                    notes.deletePage(page.id, from: noteID)
                    index = max(0, min(current, note.pages.count - 2))
                }
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { return }
                    controller.flush()
                    try notes.addImagePage(data, to: noteID, after: current)
                    forward = true
                    withAnimation(.snappy) { index = current + 1 }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(item: $share) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.medium, .large])
        }
        .errorAlert($errorMessage)
    }

    // MARK: Bars

    private func topBar(_ note: Note, _ page: NotePage) -> some View {
        HStack(spacing: 6) {
            barButton("chevron.down") {
                controller.flush()
                dismiss()
            }
            Button {
                name = note.name
                renaming = true
            } label: {
                Text(note.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            barButton("arrow.uturn.backward") { controller.undo() }
                .disabled(!controller.canUndo)
            barButton("arrow.uturn.forward") { controller.redo() }
                .disabled(!controller.canRedo)
            Menu {
                if page.pdfPage == nil, page.image == nil {
                    Picker("用紙", selection: Binding(
                        get: { page.paper },
                        set: { notes.setPaper($0, page: page.id, in: noteID) }
                    )) {
                        ForEach(NotePaper.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                Button("画像のページを追加", systemImage: "photo") { showPhotos = true }
                Divider()
                Button("PDFで書き出し", systemImage: "doc") {
                    export { try notes.exportPDF(note) }
                }
                Button("このページを画像で書き出し", systemImage: "square.and.arrow.up") {
                    export { try notes.exportImage(page, in: note) }
                }
                Divider()
                Button("このページを削除", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
    }

    private func barButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .tint(Color.brand)
    }

    /// The tools' options (when open), the page buttons, then the tools.
    private func bottomBar(_ note: Note, _ current: Int) -> some View {
        VStack(spacing: 10) {
            if showOptions {
                options
                    .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            }
            pager(note, current)
            toolbar
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.25), value: showOptions)
    }

    private func pager(_ note: Note, _ current: Int) -> some View {
        let last = current == note.pages.count - 1
        return HStack(spacing: 4) {
            Button { turn(-1, in: note) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 32)
                    .contentShape(Rectangle())
            }
            .disabled(current == 0)
            Text("\(current + 1) / \(note.pages.count)")
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(current)))
            // Past the last page, this adds one.
            Button {
                if last {
                    controller.flush()
                    notes.addPage(to: noteID, after: current)
                    forward = true
                    withAnimation(.snappy) { index = current + 1 }
                } else {
                    turn(1, in: note)
                }
            } label: {
                Image(systemName: last ? "plus" : "chevron.right")
                    .frame(width: 36, height: 32)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .tint(Color.brand)
        .glassEffect(.regular, in: .capsule)
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            ForEach([NoteTool.pen, .marker, .eraser, .lasso], id: \.self) { item in
                Button {
                    // Tapping the tool in use opens its options.
                    if tool == item {
                        if item != .lasso { showOptions.toggle() }
                    } else {
                        tool = item
                        showOptions = false
                    }
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tool == item ? Color.white : Color.primary)
                        .frame(width: 48, height: 44)
                        .background {
                            if tool == item { Capsule().fill(Color.brand) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider()
                .frame(height: 24)
                .padding(.horizontal, 6)
            // The ink in use; opens the colors and widths.
            Button {
                if tool != .pen, tool != .marker { tool = .pen }
                showOptions.toggle()
            } label: {
                Circle()
                    .fill(Color(notesHex: tool == .marker ? markerColor : penColor))
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .glassEffect(.regular, in: .capsule)
        .animation(.snappy(duration: 0.2), value: tool)
    }

    @ViewBuilder
    private var options: some View {
        VStack(spacing: 12) {
            switch tool {
            case .pen:
                colorRow($penColor)
                widthRow($penWidth, Self.penWidths, scale: 2.2)
            case .marker:
                colorRow($markerColor)
                widthRow($markerWidth, Self.markerWidths, scale: 0.7)
            case .eraser:
                Picker("消し方", selection: $eraserWhole) {
                    Text("線ごと").tag(true)
                    Text("なぞった所だけ").tag(false)
                }
                .pickerStyle(.segmented)
            case .lasso:
                EmptyView()
            }
        }
        .padding(14)
        .frame(maxWidth: 340)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func colorRow(_ selection: Binding<Int>) -> some View {
        HStack(spacing: 0) {
            ForEach(Self.colors, id: \.self) { hex in
                Button { selection.wrappedValue = hex } label: {
                    Circle()
                        .fill(Color(notesHex: hex))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                        .padding(3)
                        .overlay {
                            if selection.wrappedValue == hex { Circle().strokeBorder(Color.brand, lineWidth: 2) }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func widthRow(_ selection: Binding<Double>, _ widths: [Double], scale: Double) -> some View {
        HStack(spacing: 0) {
            ForEach(widths, id: \.self) { width in
                Button { selection.wrappedValue = width } label: {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 4 + width * scale, height: 4 + width * scale)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if selection.wrappedValue == width { Capsule().fill(Color.brand.opacity(0.18)) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Tools

    private var pkTool: any PKTool {
        switch tool {
        case .pen: PKInkingTool(.pen, color: UIColor(notesHex: penColor), width: penWidth)
        case .marker: PKInkingTool(.marker, color: UIColor(notesHex: markerColor), width: markerWidth)
        case .eraser: eraserWhole ? PKEraserTool(.vector) : PKEraserTool(.bitmap, width: 20)
        case .lasso: PKLassoTool()
        }
    }

    private var toolKey: String {
        switch tool {
        case .pen: "pen-\(penColor)-\(penWidth)"
        case .marker: "marker-\(markerColor)-\(markerWidth)"
        case .eraser: "eraser-\(eraserWhole)"
        case .lasso: "lasso"
        }
    }

    // MARK: Actions

    private func turn(_ step: Int, in note: Note) {
        let current = min(index, note.pages.count - 1)
        let target = current + step
        guard note.pages.indices.contains(target) else { return }
        forward = step > 0
        withAnimation(.snappy(duration: 0.3)) { index = target }
    }

    private func export(_ make: () throws -> URL) {
        controller.flush()
        do {
            share = NoteShare(url: try make())
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The system share sheet.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension UIColor {
    /// 0xRRGGBB, the same in light and dark: ink is always on white paper.
    convenience init(notesHex hex: Int) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(notesHex hex: Int) {
        self.init(uiColor: UIColor(notesHex: hex))
    }
}

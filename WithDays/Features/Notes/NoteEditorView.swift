import PencilKit
import PhotosUI
import SwiftUI

enum NoteTool: String, CaseIterable, Identifiable {
    case pen, marker, eraser, lasso, tape, text

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pen: "pencil.tip"
        case .marker: "highlighter"
        case .eraser: "eraser"
        case .lasso: "lasso"
        case .tape: "eye.slash"
        case .text: "textformat"
        }
    }
}

/// The edge the toolbar sits on; on the sides it stands upright.
enum NoteDock: String {
    case top, bottom, left, right

    var vertical: Bool { self == .left || self == .right }

    var alignment: Alignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }
}

/// A file handed to the share sheet.
struct NoteShare: Identifiable {
    let url: URL
    var id: URL { url }
}

/// A note open for writing: one page at a time, turned with a two-finger swipe or the page buttons.
/// The toolbar can be dragged by its grip to any edge.
struct NoteEditorView: View {
    let noteID: String

    @Environment(NotesStore.self) private var notes
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    /// Which way the last turn went, for the slide.
    @State private var forward = true
    @State private var controller = NoteCanvasController()
    @State private var tool = NoteTool.pen
    @State private var settings = NoteToolSettings.load()
    @State private var showOptions = false
    /// How far the toolbar has been dragged from its edge.
    @State private var dragOffset = CGSize.zero

    @State private var renaming = false
    @State private var name = ""
    @State private var confirmDelete = false
    @State private var showPhotos = false
    @State private var photo: PhotosPickerItem?
    @State private var showScanner = false
    @State private var share: NoteShare?
    @State private var errorMessage: String?

    private var dock: NoteDock { NoteDock(rawValue: settings.dock) ?? .bottom }

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
        let main = VStack(spacing: 0) {
            topBar(note, page)
            workspace(note, page, current)
        }
        .background(Color(uiColor: .systemBackground))
        // Typing in a text box: the page scrolls it clear of the keyboard itself.
        .ignoresSafeArea(.keyboard)
        .onChange(of: settings) { _, new in new.save() }
        .sensoryFeedback(.selection, trigger: tool)
        .sensoryFeedback(.impact(weight: .light), trigger: page.id)
        .sensoryFeedback(.impact(weight: .medium), trigger: settings.dock)
        return dialogs(imports(main, current), note, page, current)
    }

    /// The page, with the toolbar on its edge and the page buttons at the bottom.
    private func workspace(_ note: Note, _ page: NotePage, _ current: Int) -> some View {
        GeometryReader { geo in
            // The page runs under the home indicator; the bars stay above it.
            Color.clear
                .background {
                    ZStack {
                        Color(uiColor: .systemGray5)
                        canvas(note, page)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            .overlay(alignment: .bottom) {
                if dock != .bottom {
                    pager(note, current)
                        .padding(.bottom, 8)
                }
            }
            .overlay(alignment: dock.alignment) { docked(note, current, geo.size) }
            .coordinateSpace(.named("notes"))
            .animation(.snappy(duration: 0.25), value: showOptions)
        }
    }

    private func canvas(_ note: Note, _ page: NotePage) -> some View {
        NoteCanvas(
            page: page,
            pdf: notes.pdfPage(for: page, in: note),
            image: notes.image(for: page, in: note),
            tool: tool,
            settings: settings,
            controller: controller,
            load: { notes.drawing(noteID, page.id) },
            save: { notes.saveDrawing($0, noteID, page.id) },
            loadItems: { notes.items(noteID, page.id) },
            saveItems: { notes.saveItems($0, noteID, page.id) },
            onTurn: { turn($0, in: note) }
        )
        .id(page.id)
        .transition(.asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading),
            removal: .move(edge: forward ? .leading : .trailing)
        ))
    }

    private func imports<V: View>(_ view: V, _ current: Int) -> some View {
        view
            .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images)
            .onChange(of: photo) { _, item in
                guard let item else { return }
                photo = nil
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                            throw NotesStore.Failure(message: "画像を読み込めませんでした")
                        }
                        addImages([image], after: current)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner { images in
                    showScanner = false
                    if !images.isEmpty { addImages(images, after: current) }
                }
                .ignoresSafeArea()
            }
    }

    private func dialogs<V: View>(_ view: V, _ note: Note, _ page: NotePage, _ current: Int) -> some View {
        view
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
            .sheet(item: $share) { item in
                ActivityView(items: [item.url])
                    .presentationDetents([.medium, .large])
            }
            .errorAlert($errorMessage)
    }

    // MARK: Top bar

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
            pageMenu(note, page)
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
    }

    private func pageMenu(_ note: Note, _ page: NotePage) -> some View {
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
            if DocumentScanner.isSupported {
                Button("書類をスキャン", systemImage: "doc.viewfinder") {
                    controller.flush()
                    showScanner = true
                }
            }
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

    private func barButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .tint(Color.brand)
    }

    // MARK: Toolbar

    /// The toolbar on its edge, with the tool's options next to it when open.
    /// At the bottom the page buttons sit between them.
    @ViewBuilder
    private func docked(_ note: Note, _ current: Int, _ size: CGSize) -> some View {
        switch dock {
        case .bottom:
            VStack(spacing: 10) {
                optionsPanel(anchor: .bottom)
                pager(note, current)
                toolbar(size)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        case .top:
            VStack(spacing: 10) {
                toolbar(size)
                optionsPanel(anchor: .top)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        case .left:
            HStack(spacing: 10) {
                toolbar(size)
                optionsPanel(anchor: .leading)
            }
            .padding(.horizontal, 8)
        case .right:
            HStack(spacing: 10) {
                optionsPanel(anchor: .trailing)
                toolbar(size)
            }
            .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private func optionsPanel(anchor: UnitPoint) -> some View {
        if showOptions, tool != .lasso {
            NoteToolOptions(tool: tool, settings: $settings)
                .transition(.scale(scale: 0.9, anchor: anchor).combined(with: .opacity))
        }
    }

    private func toolbar(_ size: CGSize) -> some View {
        let vertical = dock.vertical
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        return layout {
            grip(size)
            ForEach(NoteTool.allCases) { toolButton($0) }
            inkButton
        }
        .padding(vertical ? .vertical : .horizontal, 8)
        .frame(width: vertical ? 52 : nil, height: vertical ? nil : 52)
        .glassEffect(.regular, in: .capsule)
        .offset(dragOffset)
        .animation(.snappy(duration: 0.2), value: tool)
    }

    /// Dragging this moves the toolbar; let go and it settles on the nearest edge.
    private func grip(_ size: CGSize) -> some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(dock.vertical ? 0 : 90))
            .frame(width: dock.vertical ? 40 : 22, height: dock.vertical ? 22 : 40)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("notes"))
                    .onChanged { value in
                        showOptions = false
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        let point = value.location
                        let edges: [(NoteDock, CGFloat)] = [
                            (.left, point.x), (.right, size.width - point.x),
                            (.top, point.y), (.bottom, size.height - point.y),
                        ]
                        let nearest = edges.min { $0.1 < $1.1 }?.0 ?? .bottom
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            settings.dock = nearest.rawValue
                            dragOffset = .zero
                        }
                    }
            )
    }

    private func toolButton(_ item: NoteTool) -> some View {
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tool == item ? Color.white : Color.primary)
                .frame(width: 40, height: 40)
                .background {
                    if tool == item { Circle().fill(Color.brand) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The color in use; opens the options.
    private var inkButton: some View {
        let hex: Int = switch tool {
        case .marker: settings.marker.color
        case .tape: settings.tape.color
        case .text: settings.text.color
        default: settings.pen.color
        }
        return Button {
            if tool == .eraser || tool == .lasso { tool = .pen }
            showOptions.toggle()
        } label: {
            Circle()
                .fill(Color(notesHex: hex))
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    // MARK: Actions

    private func turn(_ step: Int, in note: Note) {
        let current = min(index, note.pages.count - 1)
        let target = current + step
        guard note.pages.indices.contains(target) else { return }
        forward = step > 0
        withAnimation(.snappy(duration: 0.3)) { index = target }
    }

    /// Photos or scans become pages after this one; the first of them is shown.
    private func addImages(_ images: [UIImage], after current: Int) {
        controller.flush()
        do {
            try notes.addImagePages(images, to: noteID, after: current)
            forward = true
            withAnimation(.snappy) { index = current + 1 }
        } catch {
            errorMessage = error.localizedDescription
        }
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

import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Opens a deck in the editor.
struct EditorScreen: View {
    let deckID: UUID
    let startSlide: Int
    @Binding var path: [SlidesRoute]

    @Environment(\.modelContext) private var context
    @State private var editor: DeckEditor?

    var body: some View {
        Group {
            if let editor {
                EditorView(editor: editor, path: $path)
            } else {
                ProgressView()
            }
        }
        .task {
            guard editor == nil else { return }
            let id = deckID
            let decks = (try? context.fetch(FetchDescriptor<Deck>(predicate: #Predicate { $0.id == id }))) ?? []
            if let deck = decks.first {
                editor = DeckEditor(deck: deck, context: context, start: startSlide)
            } else {
                if !path.isEmpty { path.removeLast() }
            }
        }
    }
}

/// スライド作成画面: the slide in the middle, the page strip along the bottom, and glass controls on top.
struct EditorView: View {
    @Bindable var editor: DeckEditor
    @Binding var path: [SlidesRoute]

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var textController = TextEditingController()
    @State private var sheet: EditorSheet?
    @State private var renaming = false
    @State private var playing = false
    @State private var export: ExportRequest?
    @State private var showPhotos = false
    @State private var photo: PhotosPickerItem?
    @State private var importingImage = false
    @State private var selectAllOnEdit = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SlideCanvasView(editor: editor, textController: textController, showsGuides: editor.deck.showsGuides, selectAllOnEdit: $selectAllOnEdit)
                .background(Color(uiColor: .systemGroupedBackground))
            if editor.editing != nil {
                TextAccessoryBar(controller: textController) {
                    sheet = .textFormat
                } done: {
                    finishTyping()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                ContextToolbar(editor: editor) { sheet = $0 }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color(uiColor: .systemGroupedBackground))
                PageStrip(editor: editor)
            }
        }
        .animation(.snappy(duration: 0.25), value: editor.editing != nil)
        .navigationBarBackButtonHidden()
        .toolbar { toolbar }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
        .sheet(isPresented: $renaming) {
            TitleInputView(mode: .rename, initial: editor.deck.title) { title in
                DeckActions.rename(editor.deck, to: title, context: context)
            }
            .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $playing) {
            PlayerView(slides: editor.slides, deck: editor.deckID, start: editor.currentIndex) { index in
                editor.currentIndex = index
                playing = false
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { return }
                    try editor.insertImage(data)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .fileImporter(isPresented: $importingImage, allowedContentTypes: [.image]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try editor.insertImage(try Data(contentsOf: url))
            } catch {
                errorMessage = (error as? SlidesFiles.Failure)?.message ?? "画像を読み込めませんでした。"
            }
        }
        .deckExport($export)
        .alert("エラー", isPresented: Binding(get: { errorMessage != nil || editor.saveError != nil }, set: { if !$0 { errorMessage = nil; editor.saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? editor.saveError ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { editor.saveNow() }
        }
        .onDisappear { editor.saveNow() }
        .onChange(of: editor.editing) { old, new in
            // Typing ended some other way (another slide, undo): the text view lets go of the keyboard.
            if new == nil, old != nil { textController.finish() }
        }
        .sensoryFeedback(.selection, trigger: editor.selection)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                finishTyping()
                editor.saveNow()
                if !path.isEmpty { path.removeLast() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("戻る")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                finishTyping()
                editor.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!editor.canUndo)
            .accessibilityLabel("取り消し")
            Button {
                finishTyping()
                editor.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!editor.canRedo)
            .accessibilityLabel("やり直し")
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                finishTyping()
                sheet = .insert
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("挿入")
            Button {
                finishTyping()
                editor.saveNow()
                playing = true
            } label: {
                Image(systemName: "play.fill")
            }
            .accessibilityLabel("再生")
            Menu {
                Button("名前を変更", systemImage: "pencil") { renaming = true }
                Button(editor.deck.showsGuides ? "ガイドを非表示" : "ガイドを表示", systemImage: "squareshape.split.2x2.dotted") {
                    editor.toggleGuides()
                }
                Button("詳細", systemImage: "info.circle") {
                    editor.saveNow()
                    sheet = .details
                }
                Menu("書き出し", systemImage: "square.and.arrow.up") {
                    Button("PDF (.pdf)") { startExport(.pdf) }
                    Button("PowerPoint (.pptx)") { startExport(.pptx) }
                }
                Button(editor.deck.isFavorite ? "お気に入りから削除" : "お気に入りに追加", systemImage: editor.deck.isFavorite ? "star.slash" : "star") {
                    editor.toggleFavorite()
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("その他")
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: EditorSheet) -> some View {
        let selected = editor.selection
        switch sheet {
        case .insert:
            InsertSheet(
                insertText: insertText,
                insertImageFromPhotos: { showPhotos = true },
                insertImageFromFiles: { importingImage = true },
                insertShape: insertShape,
                insertLine: insertLine,
                insertTable: insertTable
            )
            .presentationDetents([.medium, .large])
        case .textFormat:
            if let selected {
                TextFormatSheet(formatter: TextFormatter(editor: editor, controller: textController, elementID: selected))
                    .presentationDetents([.medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        case .textColor:
            if let selected {
                TextColorSheet(formatter: TextFormatter(editor: editor, controller: textController, elementID: selected))
                    .presentationDetents([.height(220)])
            }
        case .shapeFill, .shapeStroke, .shapeEffects:
            if let selected {
                ShapeFormatSheet(editor: editor, elementID: selected, tab: sheet == .shapeFill ? .fill : sheet == .shapeStroke ? .stroke : .effects)
                    .presentationDetents([.medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        case .lineFormat:
            if let selected {
                LineFormatSheet(editor: editor, elementID: selected)
                    .presentationDetents([.medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        case .imageCrop:
            if let selected {
                ImageCropSheet(editor: editor, elementID: selected)
                    .presentationDetents([.medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        case .tableSize:
            if let selected {
                TableSizeSheet(editor: editor, elementID: selected)
                    .presentationDetents([.medium, .large])
            }
        case .tableFormat:
            if let selected {
                TableFormatSheet(editor: editor, elementID: selected, formatter: TextFormatter(editor: editor, controller: textController, elementID: selected))
                    .presentationDetents([.medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        case .animation:
            if let selected {
                AnimationSheet(editor: editor, elementID: selected)
                    .presentationDetents([.medium, .large])
            }
        case .background:
            BackgroundSheet(editor: editor)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        case .transition:
            TransitionSheet(editor: editor)
                .presentationDetents([.medium, .large])
        case .details:
            DeckDetailsSheet(deck: editor.deck)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Inserting

    private func insertText() {
        editor.insert(SlideElement(
            frame: SlideRect(x: 0, y: 0, width: 900, height: 140),
            content: .text(TextBoxElement(text: .plain("テキスト", size: 56)))
        ))
        if let id = editor.selection {
            selectAllOnEdit = true
            editor.editing = .text(id)
        }
    }

    private func insertShape(_ kind: ShapeKind) {
        let size: CGSize = switch kind {
        case .arrow: CGSize(width: 520, height: 300)
        case .rect, .roundRect: CGSize(width: 520, height: 360)
        default: CGSize(width: 400, height: 400)
        }
        editor.insert(SlideElement(
            frame: SlideRect(x: 0, y: 0, width: Double(size.width), height: Double(size.height)),
            content: .shape(ShapeElement(kind: kind))
        ))
    }

    private func insertLine(startArrow: Bool, endArrow: Bool) {
        var element = SlideElement(
            frame: SlideRect(x: 0, y: 0, width: 0, height: 0),
            content: .line(LineElement(start: SlidePoint(x: 710, y: 540), end: SlidePoint(x: 1210, y: 540), startArrow: startArrow, endArrow: endArrow))
        )
        element.syncLineFrame()
        editor.insert(element)
    }

    private func insertTable(rows: Int, columns: Int) {
        let width = min(Double(columns) * 280, 1600)
        let height = min(Double(rows) * 110, 860)
        editor.insert(SlideElement(
            frame: SlideRect(x: 0, y: 0, width: width, height: height),
            content: .table(.make(rows: rows, columns: columns))
        ))
    }

    private func startExport(_ format: ExportFormat) {
        finishTyping()
        editor.saveNow()
        export = ExportRequest(deck: editor.deck, format: format)
    }

    private func finishTyping() {
        guard editor.editing != nil else { return }
        textController.finish()
        editor.editing = nil
    }
}

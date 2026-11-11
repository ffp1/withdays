import PDFKit
import PencilKit
import SwiftUI

/// Notes' folders, notes and pages, saved through `NotesData` after every change.
/// Strokes, imported PDFs and images are files in each note's folder.
@MainActor
@Observable
final class NotesStore {
    private(set) var state = NotesData.load()

    /// The text read from each page, by page ID; a page that isn't here hasn't been read yet (or has changed).
    private(set) var pageTexts = NotesData.loadTexts()
    /// How far reading the pages has got, while it's running.
    private(set) var reading: (done: Int, total: Int)?

    @ObservationIgnored private var documents: [String: PDFDocument] = [:]
    @ObservationIgnored private let thumbnails = NSCache<NSString, UIImage>()
    @ObservationIgnored private let pageThumbnails = NSCache<NSString, UIImage>()

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    var folders: [NoteFolder] { state.folders }

    /// Newest first.
    func notes(in folder: String?) -> [Note] {
        state.notes.filter { $0.folder == folder }.sorted { $0.updated > $1.updated }
    }

    func note(_ id: String) -> Note? {
        state.notes.first { $0.id == id }
    }

    // MARK: Folders

    func addFolder(name: String) {
        state.folders.append(NoteFolder(id: NotesData.newID("folder"), name: name))
        persist()
    }

    func renameFolder(_ id: String, to name: String) {
        guard let index = state.folders.firstIndex(where: { $0.id == id }) else { return }
        state.folders[index].name = name
        persist()
    }

    /// Deletes the folder and the notes in it.
    func deleteFolder(_ id: String) {
        for note in state.notes where note.folder == id { removeFiles(of: note.id) }
        state.notes.removeAll { $0.folder == id }
        state.folders.removeAll { $0.id == id }
        persist()
    }

    // MARK: Notes

    @discardableResult
    func addNote(name: String, folder: String?, paper: NotePaper) -> Note {
        let note = Note(
            id: NotesData.newID("note"), name: name, folder: folder,
            pages: [NotePage(id: NotesData.newID("page"), paper: paper)],
            paper: paper, pdf: nil, created: .now, updated: .now
        )
        state.notes.append(note)
        persist()
        return note
    }

    func rename(_ noteID: String, to name: String) {
        mutate(noteID) { $0.name = name }
    }

    func move(_ noteID: String, to folder: String?) {
        mutate(noteID) { $0.folder = folder }
    }

    func delete(_ noteID: String) {
        state.notes.removeAll { $0.id == noteID }
        removeFiles(of: noteID)
        persist()
    }

    /// A note from a PDF: one page for each of its pages, at their own sizes.
    @discardableResult
    func importPDF(from url: URL, folder: String?) throws -> Note {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let id = NotesData.newID("note")
        let target = NotesData.folder(of: id).appending(path: "source.pdf")
        do {
            try FileManager.default.copyItem(at: url, to: target)
        } catch {
            removeFiles(of: id)
            throw Failure(message: "PDFを読み込めませんでした")
        }
        guard let document = PDFDocument(url: target), document.pageCount > 0, !document.isLocked else {
            removeFiles(of: id)
            throw Failure(message: "このPDFは開けませんでした")
        }
        var pages: [NotePage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let box = page.bounds(for: .cropBox)
            let turned = page.rotation % 180 != 0
            pages.append(NotePage(
                id: NotesData.newID("page"), paper: .plain, pdfPage: index,
                width: turned ? box.height : box.width, height: turned ? box.width : box.height
            ))
        }
        let note = Note(
            id: id, name: url.deletingPathExtension().lastPathComponent, folder: folder,
            pages: pages, paper: .plain, pdf: "source.pdf", created: .now, updated: .now
        )
        documents[id] = document
        state.notes.append(note)
        persist()
        return note
    }

    /// A note from photos or scans: one page for each, the image's own shape.
    @discardableResult
    func importImages(_ images: [UIImage], name: String, folder: String?) throws -> Note {
        guard !images.isEmpty else { throw Failure(message: "画像を読み込めませんでした") }
        let id = NotesData.newID("note")
        do {
            let pages = try images.map { try imagePage($0, noteID: id) }
            let note = Note(id: id, name: name, folder: folder, pages: pages, paper: .plain, pdf: nil, created: .now, updated: .now)
            state.notes.append(note)
            persist()
            return note
        } catch {
            removeFiles(of: id)
            throw error
        }
    }

    // MARK: Pages

    /// A blank page after `index`, on the note's paper.
    @discardableResult
    func addPage(to noteID: String, after index: Int) -> NotePage? {
        guard let note = note(noteID) else { return nil }
        let page = NotePage(id: NotesData.newID("page"), paper: note.paper)
        mutate(noteID) { $0.pages.insert(page, at: min(index + 1, $0.pages.count)) }
        return page
    }

    /// Pages with the images under the handwriting, after `index`, each the image's own shape.
    func addImagePages(_ images: [UIImage], to noteID: String, after index: Int) throws {
        guard !images.isEmpty else { throw Failure(message: "画像を読み込めませんでした") }
        let pages = try images.map { try imagePage($0, noteID: noteID) }
        mutate(noteID) { $0.pages.insert(contentsOf: pages, at: min(index + 1, $0.pages.count)) }
    }

    func movePage(in noteID: String, from source: Int, to destination: Int) {
        mutate(noteID) { note in
            guard note.pages.indices.contains(source), note.pages.indices.contains(destination), source != destination else { return }
            note.pages.insert(note.pages.remove(at: source), at: destination)
        }
    }

    /// A copy right after the page, with its handwriting, tapes, text boxes and image.
    func duplicatePage(_ pageID: String, in noteID: String) {
        guard let note = note(noteID), let index = note.pages.firstIndex(where: { $0.id == pageID }) else { return }
        var copy = note.pages[index]
        copy.id = NotesData.newID("page")
        let folder = NotesData.folder(of: noteID)
        let files = FileManager.default
        try? files.copyItem(at: NotesData.drawingURL(noteID, pageID), to: NotesData.drawingURL(noteID, copy.id))
        try? files.copyItem(at: NotesData.itemsURL(noteID, pageID), to: NotesData.itemsURL(noteID, copy.id))
        if let image = copy.image {
            let name = "\(copy.id).jpg"
            try? files.copyItem(at: folder.appending(path: image), to: folder.appending(path: name))
            copy.image = name
        }
        if let text = pageTexts[pageID] { pageTexts[copy.id] = text }
        mutate(noteID) { $0.pages.insert(copy, at: index + 1) }
    }

    /// A note keeps at least one page; deleting the last one leaves a blank page.
    func deletePage(_ pageID: String, from noteID: String) {
        guard let note = note(noteID), let page = note.pages.first(where: { $0.id == pageID }) else { return }
        try? FileManager.default.removeItem(at: NotesData.drawingURL(noteID, pageID))
        try? FileManager.default.removeItem(at: NotesData.itemsURL(noteID, pageID))
        forgetText(of: pageID)
        if let image = page.image { try? FileManager.default.removeItem(at: NotesData.folder(of: noteID).appending(path: image)) }
        mutate(noteID) { note in
            note.pages.removeAll { $0.id == pageID }
            if note.pages.isEmpty { note.pages = [NotePage(id: NotesData.newID("page"), paper: note.paper)] }
        }
    }

    /// Changes this page's ruling, and what new pages get.
    func setPaper(_ paper: NotePaper, page pageID: String, in noteID: String) {
        mutate(noteID) { note in
            note.paper = paper
            if let index = note.pages.firstIndex(where: { $0.id == pageID }) { note.pages[index].paper = paper }
        }
        pageThumbnails.removeObject(forKey: pageID as NSString)
    }

    // MARK: Strokes and backgrounds

    func drawing(_ noteID: String, _ pageID: String) -> PKDrawing {
        guard let data = try? Data(contentsOf: NotesData.drawingURL(noteID, pageID)), let drawing = try? PKDrawing(data: data) else {
            return PKDrawing()
        }
        return drawing
    }

    func saveDrawing(_ drawing: PKDrawing, _ noteID: String, _ pageID: String) {
        try? drawing.dataRepresentation().write(to: NotesData.drawingURL(noteID, pageID), options: .atomic)
        forgetText(of: pageID)
        mutate(noteID) { $0.updated = .now }
    }

    /// The page's tapes and text boxes.
    func items(_ noteID: String, _ pageID: String) -> NoteItems {
        guard let data = try? Data(contentsOf: NotesData.itemsURL(noteID, pageID)),
              let items = try? JSONDecoder().decode(NoteItems.self, from: data) else {
            return NoteItems()
        }
        return items
    }

    func saveItems(_ items: NoteItems, _ noteID: String, _ pageID: String) {
        let url = NotesData.itemsURL(noteID, pageID)
        if items.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: url, options: .atomic)
        }
        forgetText(of: pageID)
        mutate(noteID) { $0.updated = .now }
    }

    func pdfPage(for page: NotePage, in note: Note) -> PDFPage? {
        guard let index = page.pdfPage, let file = note.pdf else { return nil }
        if documents[note.id] == nil {
            documents[note.id] = PDFDocument(url: NotesData.folder(of: note.id).appending(path: file))
        }
        return documents[note.id]?.page(at: index)
    }

    func image(for page: NotePage, in note: Note) -> UIImage? {
        guard let file = page.image else { return nil }
        return UIImage(contentsOfFile: NotesData.folder(of: note.id).appending(path: file).path)
    }

    // MARK: Rendering

    /// The first page, small, for the library.
    func thumbnail(of note: Note) -> UIImage? {
        if let cached = thumbnails.object(forKey: note.id as NSString) { return cached }
        guard let page = note.pages.first else { return nil }
        let image = render(page, in: note, scale: 240 / page.size.width)
        thumbnails.setObject(image, forKey: note.id as NSString)
        return image
    }

    /// One page, small, for the page list.
    func thumbnail(of page: NotePage, in note: Note) -> UIImage {
        if let cached = pageThumbnails.object(forKey: page.id as NSString) { return cached }
        let image = render(page, in: note, scale: 200 / page.size.width)
        pageThumbnails.setObject(image, forKey: page.id as NSString)
        return image
    }

    // MARK: Text in pages

    /// Notes whose name or pages contain the text, newest first, with the first page that has it.
    func search(_ query: String) -> [(note: Note, page: Int?)] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .widthInsensitive]
        return state.notes.sorted { $0.updated > $1.updated }.compactMap { note -> (note: Note, page: Int?)? in
            if let page = note.pages.firstIndex(where: { pageTexts[$0.id]?.range(of: needle, options: options) != nil }) {
                return (note, page)
            }
            return note.name.range(of: needle, options: options) != nil ? (note, nil) : nil
        }
    }

    /// Reads the pages that haven't been read since they last changed, one at a time.
    func readPages() async {
        guard reading == nil else { return }
        let waiting = state.notes.flatMap { note in
            note.pages.filter { pageTexts[$0.id] == nil }.map { (note.id, $0.id) }
        }
        guard !waiting.isEmpty else { return }
        reading = (0, waiting.count)
        defer {
            reading = nil
            NotesData.saveTexts(pageTexts)
        }
        for (done, (noteID, pageID)) in waiting.enumerated() {
            guard !Task.isCancelled else { return }
            reading = (done, waiting.count)
            // The note or page may have gone, or been read, in the meantime.
            guard let note = note(noteID), let page = note.pages.first(where: { $0.id == pageID }), pageTexts[pageID] == nil else { continue }
            pageTexts[pageID] = await text(of: page, in: note)
            if done % 10 == 9 { NotesData.saveTexts(pageTexts) }
            await Task.yield()
        }
    }

    /// The text on a page: print in its PDF / image, handwriting, and text boxes.
    func text(of page: NotePage, in note: Note) async -> String {
        let blank = page.pdfPage == nil && page.image == nil
            && drawing(note.id, page.id).strokes.isEmpty && items(note.id, page.id).texts.isEmpty
        guard !blank else { return "" }
        return await NoteOCR.recognize(render(page, in: note, scale: 2))
    }

    /// The page changed: what was read from it no longer holds.
    private func forgetText(of pageID: String) {
        pageThumbnails.removeObject(forKey: pageID as NSString)
        guard pageTexts[pageID] != nil else { return }
        pageTexts[pageID] = nil
        NotesData.saveTexts(pageTexts)
    }

    /// The page with its handwriting; `scale` is pixels per point.
    func render(_ page: NotePage, in note: Note, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let rect = CGRect(origin: .zero, size: page.size)
        let strokes = drawing(note.id, page.id)
        let overlay = items(note.id, page.id)
        let pdf = pdfPage(for: page, in: note)
        let image = image(for: page, in: note)
        return UIGraphicsImageRenderer(size: page.size, format: format).image { context in
            NotePaperRenderer.draw(page, pdf: pdf, image: image, in: context.cgContext)
            if !strokes.strokes.isEmpty {
                // Ink keeps its colors: the paper is always white.
                var ink = UIImage()
                UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                    ink = strokes.image(from: rect, scale: max(scale, 1))
                }
                ink.draw(in: rect)
            }
            NoteItemsRenderer.draw(overlay, in: context.cgContext)
        }
    }

    /// The whole note as a PDF in the temporary folder.
    func exportPDF(_ note: Note) throws -> URL {
        let url = exportURL(note.name, "pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: NotePage.a4))
        try renderer.writePDF(to: url) { context in
            for page in note.pages {
                let rect = CGRect(origin: .zero, size: page.size)
                context.beginPage(withBounds: rect, pageInfo: [:])
                NotePaperRenderer.draw(page, pdf: pdfPage(for: page, in: note), image: image(for: page, in: note), in: context.cgContext)
                let strokes = drawing(note.id, page.id)
                if !strokes.strokes.isEmpty {
                    var ink = UIImage()
                    UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                        ink = strokes.image(from: rect, scale: 3)
                    }
                    ink.draw(in: rect)
                }
                NoteItemsRenderer.draw(items(note.id, page.id), in: context.cgContext)
            }
        }
        return url
    }

    /// One page as a PNG in the temporary folder.
    func exportImage(_ page: NotePage, in note: Note) throws -> URL {
        let index = (note.pages.firstIndex(of: page) ?? 0) + 1
        let url = exportURL("\(note.name) \(index)", "png")
        guard let data = render(page, in: note, scale: 3).pngData() else { throw Failure(message: "画像を書き出せませんでした") }
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: Private

    private func exportURL(_ name: String, _ ext: String) -> URL {
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
        let folder = FileManager.default.temporaryDirectory.appending(path: "NotesExport")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "\(safe.isEmpty ? "Note" : safe).\(ext)")
    }

    /// A page the image's shape (its long side an A4's), with the image saved upright and
    /// no larger than needed as a JPEG next to the strokes.
    private func imagePage(_ image: UIImage, noteID: String) throws -> NotePage {
        guard image.size.width > 0, image.size.height > 0 else {
            throw Failure(message: "画像を読み込めませんでした")
        }
        let pageID = NotesData.newID("page")
        let fit = NotePage.a4.height / max(image.size.width, image.size.height)
        let limit: CGFloat = 2400
        let scale = min(1, limit / max(image.size.width * image.scale, image.size.height * image.scale))
        let size = CGSize(width: image.size.width * image.scale * scale, height: image.size.height * image.scale * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = upright.jpegData(compressionQuality: 0.85) else { throw Failure(message: "画像を読み込めませんでした") }
        let file = "\(pageID).jpg"
        try jpeg.write(to: NotesData.folder(of: noteID).appending(path: file), options: .atomic)
        return NotePage(
            id: pageID, paper: .plain, image: file,
            width: Double(image.size.width * fit), height: Double(image.size.height * fit)
        )
    }

    private func removeFiles(of noteID: String) {
        documents[noteID] = nil
        thumbnails.removeObject(forKey: noteID as NSString)
        try? FileManager.default.removeItem(at: NotesData.root.appending(path: noteID))
    }

    private func mutate(_ noteID: String, _ change: (inout Note) -> Void) {
        guard let index = state.notes.firstIndex(where: { $0.id == noteID }) else { return }
        change(&state.notes[index])
        thumbnails.removeObject(forKey: noteID as NSString)
        persist()
    }

    private func persist() {
        NotesData.save(state)
    }
}

import PDFKit
import UIKit

/// What a page is ruled with.
enum NotePaper: String, Codable, CaseIterable, Identifiable {
    case plain, ruled, grid, dot

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plain: "無地"
        case .ruled: "罫線"
        case .grid: "方眼"
        case .dot: "ドット"
        }
    }
}

/// One page: its paper, or the PDF page / image under the handwriting. The strokes are in a file of their own.
struct NotePage: Codable, Identifiable, Hashable {
    var id: String
    var paper: NotePaper
    /// Index into the note's imported PDF.
    var pdfPage: Int?
    /// File name of an imported image, in the note's folder.
    var image: String?
    /// Points; A4 portrait unless it came from a PDF.
    var width: Double = NotePage.a4.width
    var height: Double = NotePage.a4.height

    static let a4 = CGSize(width: 595, height: 842)

    var size: CGSize { CGSize(width: width, height: height) }
}

struct Note: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var folder: String?
    var pages: [NotePage]
    /// The paper new pages get.
    var paper: NotePaper
    /// File name of the imported PDF, in the note's folder.
    var pdf: String?
    var created: Date
    var updated: Date
}

struct NoteFolder: Codable, Identifiable, Hashable {
    var id: String
    var name: String
}

struct NotesState: Codable {
    var folders: [NoteFolder] = []
    var notes: [Note] = []
}

/// Notes live in the app's Documents folder (shown in the Files app, so they can be backed up):
/// Notes/index.json, and Notes/<note>/ with each page's strokes and any imported PDF / images.
enum NotesData {
    static let root: URL = {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Notes")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static var index: URL { root.appending(path: "index.json") }

    static func folder(of noteID: String) -> URL {
        let url = root.appending(path: noteID)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func drawingURL(_ noteID: String, _ pageID: String) -> URL {
        folder(of: noteID).appending(path: "\(pageID).drawing")
    }

    static func load() -> NotesState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: index), let state = try? decoder.decode(NotesState.self, from: data) else {
            return NotesState()
        }
        return state
    }

    static func save(_ state: NotesState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: index, options: .atomic)
    }

    static func newID(_ prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.prefix(8).lowercased())"
    }
}

/// Draws what's under the handwriting: white paper with its ruling, or the imported PDF page / image.
/// Used by the canvas (in tiles), the thumbnails and the exports, so it only touches Core Graphics and PDFKit.
enum NotePaperRenderer {
    private static let line = UIColor(red: 0.70, green: 0.76, blue: 0.84, alpha: 1).cgColor

    /// `context` has its origin at the page's top left, one unit per point.
    static func draw(_ page: NotePage, pdf: PDFPage?, image: UIImage?, in context: CGContext) {
        let size = page.size
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        if let pdf {
            let box = pdf.bounds(for: .cropBox)
            let turned = pdf.rotation % 180 != 0
            let natural = turned ? CGSize(width: box.height, height: box.width) : box.size
            guard natural.width > 0, natural.height > 0 else { return }
            context.saveGState()
            // PDF pages draw upwards from the bottom left.
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: size.width / natural.width, y: -size.height / natural.height)
            pdf.draw(with: .cropBox, to: context)
            context.restoreGState()
            return
        }
        if let image, let cgImage = image.cgImage, image.size.width > 0, image.size.height > 0 {
            // Fitted inside the page, centered.
            let scale = min(size.width / image.size.width, size.height / image.size.height)
            let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let rect = CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(origin: .zero, size: rect.size))
            context.restoreGState()
            return
        }

        context.setStrokeColor(line)
        context.setFillColor(line)
        context.setLineWidth(0.6)
        switch page.paper {
        case .plain:
            break
        case .ruled:
            var y: CGFloat = 70
            while y < size.height - 30 {
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: size.width, y: y))
                y += 28
            }
            context.strokePath()
        case .grid:
            let step: CGFloat = 20
            var x = step
            while x < size.width {
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y = step
            while y < size.height {
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.strokePath()
        case .dot:
            let step: CGFloat = 20
            var y = step
            while y < size.height {
                var x = step
                while x < size.width {
                    context.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    x += step
                }
                y += step
            }
        }
    }
}

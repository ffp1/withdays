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

/// Masking tape: a straight band that hides what's under it until it's tapped (for memorizing).
struct NoteTape: Codable, Identifiable, Hashable {
    var id: String
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double
    var width: Double
    var color: Int
    /// Tapped: see-through.
    var revealed: Bool
}

/// A box of typed text. Its height follows the text.
struct NoteText: Codable, Identifiable, Hashable {
    var id: String
    var x: Double
    var y: Double
    var width: Double
    var text: String
    var size: Double
    var color: Int
    var bold: Bool
    var background: Int?

    /// Room between the box's edge and its text, on every side.
    static let inset: CGFloat = 4

    var font: UIFont { .systemFont(ofSize: size, weight: bold ? .bold : .regular) }
}

/// What sits on a page over the handwriting, in a file of its own next to the strokes.
struct NoteItems: Codable, Hashable {
    var tapes: [NoteTape] = []
    var texts: [NoteText] = []

    var isEmpty: Bool { tapes.isEmpty && texts.isEmpty }
}

/// A color, a width and their presets (ten colors, four widths) for one tool.
struct NoteInk: Codable, Equatable {
    var color: Int
    var width: Double
    var colors: [Int]
    var widths: [Double]
}

/// The tools' settings, kept between launches.
struct NoteToolSettings: Codable, Equatable {
    static let palette = [0x1C1C1E, 0x8E8E93, 0xD12F2F, 0xF08C00, 0xFFD60A, 0x2FA84F, 0x1F7AE0, 0x7A4FD6, 0xE85D9E, 0x8B5A2B]
    static let bright = [0xFFD60A, 0xFFA94D, 0xFF8FA3, 0xF783AC, 0xB197FC, 0x74C0FC, 0x63E6BE, 0xB2F2BB, 0xFFE066, 0xCED4DA]

    var pen = NoteInk(color: 0x1C1C1E, width: 3, colors: palette, widths: [1.5, 3, 5, 8])
    var marker = NoteInk(color: 0xFFD60A, width: 16, colors: bright, widths: [10, 16, 24, 34])
    var tape = NoteInk(color: 0xFFA94D, width: 22, colors: bright, widths: [14, 22, 30, 40])
    /// For text the width is the font size.
    var text = NoteInk(color: 0x1C1C1E, width: 16, colors: palette, widths: [12, 16, 22, 30])
    var textBold = false
    var textBackground: Int?
    var eraserWidth = 20.0
    var eraserWidths = [10.0, 20, 35, 60]
    /// The eraser removes whole strokes, or only what it touches.
    var eraserWhole = true
    /// The edge the toolbar sits on: top, bottom, left or right.
    var dock = "bottom"

    static func load() -> NoteToolSettings {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.notesTools),
              let settings = try? JSONDecoder().decode(NoteToolSettings.self, from: data) else {
            return NoteToolSettings()
        }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: SettingsKey.notesTools)
    }
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

    static func itemsURL(_ noteID: String, _ pageID: String) -> URL {
        folder(of: noteID).appending(path: "\(pageID).items.json")
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

/// Draws the text boxes and tapes for thumbnails and exports; on screen the page's overlay shows them.
enum NoteItemsRenderer {
    /// `context` has its origin at the page's top left, one unit per point.
    static func draw(_ items: NoteItems, in context: CGContext) {
        guard !items.isEmpty else { return }
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        for text in items.texts {
            let inner = CGFloat(text.width) - NoteText.inset * 2
            let string = NSAttributedString(string: text.text, attributes: [
                .font: text.font,
                .foregroundColor: UIColor(notesHex: text.color),
            ])
            let bounds = string.boundingRect(
                with: CGSize(width: inner, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
            )
            let height = ceil(bounds.height)
            if let background = text.background {
                let box = CGRect(x: CGFloat(text.x), y: CGFloat(text.y), width: CGFloat(text.width), height: height + NoteText.inset * 2)
                UIColor(notesHex: background).setFill()
                UIBezierPath(roundedRect: box, cornerRadius: 4).fill()
            }
            string.draw(
                with: CGRect(x: CGFloat(text.x) + NoteText.inset, y: CGFloat(text.y) + NoteText.inset, width: inner, height: height),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
            )
        }
        for tape in items.tapes {
            context.setStrokeColor(UIColor(notesHex: tape.color).withAlphaComponent(tape.revealed ? 0.25 : 1).cgColor)
            context.setLineWidth(CGFloat(tape.width))
            context.setLineCap(.butt)
            context.move(to: CGPoint(x: tape.x1, y: tape.y1))
            context.addLine(to: CGPoint(x: tape.x2, y: tape.y2))
            context.strokePath()
        }
    }
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

    var notesHex: Int {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let part: (CGFloat) -> Int = { Int((min(max($0, 0), 1) * 255).rounded()) }
        return part(red) << 16 | part(green) << 8 | part(blue)
    }
}

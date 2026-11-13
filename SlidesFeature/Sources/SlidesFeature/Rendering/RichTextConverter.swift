import UIKit

/// Turns `RichText` into attributed strings (for drawing and editing) and back.
/// Sizes are in slide points; `scale` multiplies them for the view.
enum RichTextConverter {
    /// The font name the run asked for, kept even when the font isn't installed (re-importing it restores the look).
    static let fontNameKey = NSAttributedString.Key("slides.fontName")
    static let boldKey = NSAttributedString.Key("slides.bold")
    static let italicKey = NSAttributedString.Key("slides.italic")
    static let sizeKey = NSAttributedString.Key("slides.size")

    /// A font by PostScript name or family name ("System" for the system font), with bold / italic when the family has them.
    /// A font that isn't installed falls back to the system font.
    static func font(name: String, size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
        var base: UIFont
        if name == "System" || name.isEmpty {
            base = .systemFont(ofSize: size)
        } else if let font = UIFont(name: name, size: size) {
            base = font
        } else if let face = UIFont.fontNames(forFamilyName: name).first, let font = UIFont(name: face, size: size) {
            base = font
        } else {
            base = .systemFont(ofSize: size)
        }
        guard bold || italic else { return base }
        var traits = base.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
            base = UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    static func paragraph(_ text: RichText) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        switch text.hAlign {
        case .left: style.alignment = .left
        case .center: style.alignment = .center
        case .right: style.alignment = .right
        case .justified: style.alignment = .justified
        }
        style.lineHeightMultiple = CGFloat(max(text.lineSpacing, 0.5))
        style.lineBreakMode = .byWordWrapping
        return style
    }

    static func attributes(_ run: TextRun, in text: RichText, scale: CGFloat) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(name: run.font, size: CGFloat(run.size) * scale, bold: run.bold, italic: run.italic),
            .foregroundColor: run.color.uiColor,
            .paragraphStyle: paragraph(text),
            .kern: CGFloat(text.charSpacing) * scale,
            fontNameKey: run.font,
            boldKey: run.bold,
            italicKey: run.italic,
            sizeKey: run.size,
        ]
        if run.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if run.strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    static func attributed(_ text: RichText, scale: CGFloat = 1) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in text.runs where !run.text.isEmpty {
            result.append(NSAttributedString(string: run.text, attributes: attributes(run, in: text, scale: scale)))
        }
        return result
    }

    /// The run formatting in a set of attributes (from editing).
    static func run(from attributes: [NSAttributedString.Key: Any], scale: CGFloat, fallback: TextRun) -> TextRun {
        var run = fallback
        let font = attributes[.font] as? UIFont
        if let name = attributes[fontNameKey] as? String {
            run.font = name
        } else if let font {
            run.font = font.fontName
        }
        if let size = attributes[sizeKey] as? Double {
            run.size = size
        } else if let font {
            run.size = Double(font.pointSize / max(scale, 0.0001))
        }
        let traits = font?.fontDescriptor.symbolicTraits ?? []
        run.bold = attributes[boldKey] as? Bool ?? traits.contains(.traitBold)
        run.italic = attributes[italicKey] as? Bool ?? traits.contains(.traitItalic)
        run.underline = ((attributes[.underlineStyle] as? Int) ?? 0) != 0
        run.strike = ((attributes[.strikethroughStyle] as? Int) ?? 0) != 0
        if let color = attributes[.foregroundColor] as? UIColor { run.color = RGBA(color) }
        run.text = ""
        return run
    }

    /// The runs of edited text, keeping the box's own settings (alignment, spacing) from `base`.
    static func richText(from string: NSAttributedString, base: RichText, scale: CGFloat) -> RichText {
        var result = base
        var runs: [TextRun] = []
        let fallback = base.baseRun
        string.enumerateAttributes(in: NSRange(location: 0, length: string.length)) { attributes, range, _ in
            let text = (string.string as NSString).substring(with: range)
            runs.append(run(from: attributes, scale: scale, fallback: fallback).with(text))
        }
        result.runs = runs.isEmpty ? [fallback] : runs
        return result.compacted()
    }

    /// How tall the text is when wrapped to a width, in the same units as the text.
    static func height(of string: NSAttributedString, width: CGFloat) -> CGFloat {
        guard string.length > 0 else { return 0 }
        let bounds = string.boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
        )
        return ceil(bounds.height)
    }
}

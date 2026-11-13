import CoreGraphics
import UIKit

/// Draws slides with Core Graphics: the editor's element views, thumbnails and the PDF export all use this,
/// so a slide looks the same everywhere. Coordinates are slide points (1920×1080), y down.
/// Safe to call off the main thread: it only touches the context it's given and decoded images.
enum SlideRenderer {
    static let size = SlideContent.size
    /// Room around an element's frame for its stroke, arrowheads and shadow.
    static let padding: CGFloat = 60

    /// Enough room for this element's shadow and stroke, so nothing it draws is cut off.
    static func padding(for element: SlideElement) -> CGFloat {
        var extent: Double = 0
        switch element.content {
        case .shape(let shape):
            if let shadow = shape.shadow { extent = shadow.blur * 1.6 + max(abs(shadow.x), abs(shadow.y)) }
            extent = max(extent, (shape.stroke?.width ?? 0) * 0.75)
        case .text(let box):
            if let shadow = box.text.shadow { extent = shadow.blur * 1.6 + max(abs(shadow.x), abs(shadow.y)) }
            extent = max(extent, box.text.outline?.width ?? 0)
        default:
            break
        }
        return max(padding, CGFloat(extent) + 12)
    }

    /// `preview` draws images at screen size (thumbnails, the editor); exports leave it off for full resolution.
    static func draw(_ slide: SlideContent, deck: UUID, in context: CGContext, preview: Bool = false) {
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        drawBackground(slide.background, deck: deck, in: context, rect: CGRect(origin: .zero, size: size), preview: preview)
        for element in slide.elements {
            draw(element, deck: deck, in: context, preview: preview)
        }
    }

    static func drawBackground(_ background: SlideBackground, deck: UUID, in context: CGContext, rect: CGRect, preview: Bool = false) {
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: rect)
        // White under everything, so a see-through color or a letterboxed image still has paper.
        context.setFillColor(UIColor.white.cgColor)
        context.fill(rect)
        switch background {
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(rect)
        case .gradient(let gradient):
            drawGradient(gradient, in: rect, context: context)
        case .image(let ref):
            if let image = SlideAssets.image(ref.asset, deck: deck, preview: preview) {
                drawImage(image, in: rect, mode: ref.mode, context: context)
            }
        }
    }

    /// One element where it sits on the slide: moved, turned and faded.
    static func draw(_ element: SlideElement, deck: UUID, in context: CGContext, preview: Bool = false) {
        let frame = element.frame.cg
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: frame.midX, y: frame.midY)
        context.rotate(by: CGFloat(element.rotation) * .pi / 180)
        context.translateBy(x: -frame.width / 2, y: -frame.height / 2)
        let faded = element.opacity < 0.999
        if faded {
            context.setAlpha(CGFloat(max(element.opacity, 0)))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        drawContent(element, deck: deck, in: context, preview: preview)
        if faded { context.endTransparencyLayer() }
    }

    /// The element's content in its own space: (0, 0) is its frame's top left.
    /// `placeholders` shows an empty text box's placeholder in gray (the editor only).
    static func drawContent(_ element: SlideElement, deck: UUID, in context: CGContext, preview: Bool = false, placeholders: Bool = false) {
        let size = element.frame.cg.size
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        switch element.content {
        case .text(let box):
            if placeholders, let placeholder = box.placeholder, box.text.plainText.isEmpty {
                var shown = box.text
                var run = box.text.baseRun.with(placeholder)
                run.color = RGBA(hex: 0x9CA3AF)
                shown.runs = [run]
                drawText(shown, in: rect)
            } else {
                drawText(box.text, in: rect)
            }
        case .shape(let shape):
            drawShape(shape, in: rect, deck: deck, context: context, preview: preview)
        case .line(let line):
            let origin = element.frame.cg.origin
            drawLine(line, offset: CGPoint(x: -origin.x, y: -origin.y), context: context)
        case .image(let image):
            drawImageElement(image, in: rect, deck: deck, context: context, preview: preview)
        case .table(let table):
            drawTable(table, in: rect, context: context)
        }
    }

    // MARK: Text

    /// Wrapped to the box's width and placed by its vertical alignment. Text that doesn't fit runs past the box.
    static func drawText(_ text: RichText, in rect: CGRect, inset: CGFloat = 0) {
        let string = RichTextConverter.attributed(text)
        guard string.length > 0 else { return }
        let inner = rect.insetBy(dx: inset, dy: inset)
        let height = RichTextConverter.height(of: string, width: inner.width)
        var y = inner.minY
        switch text.vAlign {
        case .top: break
        case .middle: y = inner.midY - height / 2
        case .bottom: y = inner.maxY - height
        }
        string.draw(
            with: CGRect(x: inner.minX, y: y, width: inner.width, height: height + 1),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
        )
    }

    // MARK: Shapes

    static func drawShape(_ shape: ShapeElement, in rect: CGRect, deck: UUID, context: CGContext, preview: Bool = false) {
        let path = ShapePaths.path(shape.kind, in: rect, cornerRadius: CGFloat(shape.cornerRadius))
        context.saveGState()
        if let shadow = shape.shadow {
            context.setShadow(
                offset: CGSize(width: shadow.x, height: shadow.y), blur: CGFloat(shadow.blur), color: shadow.color.cgColor
            )
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        fill(path, with: shape.fill, in: rect, deck: deck, context: context, preview: preview)
        if let stroke = shape.stroke, stroke.width > 0 {
            context.addPath(path)
            apply(stroke, context: context)
            context.strokePath()
        }
        if shape.shadow != nil { context.endTransparencyLayer() }
        context.restoreGState()
    }

    static func fill(_ path: CGPath, with fill: Fill, in rect: CGRect, deck: UUID, context: CGContext, preview: Bool = false) {
        switch fill {
        case .none:
            break
        case .solid(let color):
            context.addPath(path)
            context.setFillColor(color.cgColor)
            context.fillPath()
        case .gradient(let gradient):
            context.saveGState()
            context.addPath(path)
            context.clip()
            drawGradient(gradient, in: rect, context: context)
            context.restoreGState()
        case .image(let ref):
            guard let image = SlideAssets.image(ref.asset, deck: deck, preview: preview) else { return }
            context.saveGState()
            context.addPath(path)
            context.clip()
            drawImage(image, in: rect, mode: ref.mode, context: context)
            context.restoreGState()
        }
    }

    static func apply(_ stroke: Stroke, context: CGContext) {
        context.setStrokeColor(stroke.color.cgColor)
        context.setLineWidth(CGFloat(stroke.width))
        context.setLineJoin(.round)
        context.setLineCap(stroke.dash == .dot ? .round : .butt)
        context.setLineDash(phase: 0, lengths: stroke.dash.pattern(width: stroke.width))
    }

    /// Fills the rect with a linear gradient at its angle, reaching the rect's corners.
    static func drawGradient(_ gradient: LinearGradientFill, in rect: CGRect, context: CGContext) {
        let stops = gradient.sortedStops
        guard let first = stops.first else { return }
        if stops.count == 1 {
            context.setFillColor(first.color.cgColor)
            context.fill(rect)
            return
        }
        let colors = stops.map(\.color.cgColor) as CFArray
        var locations = stops.map { CGFloat(min(max($0.location, 0), 1)) }
        guard let cgGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: &locations) else { return }
        let points = gradientPoints(angle: gradient.angle, in: rect)
        context.drawLinearGradient(cgGradient, start: points.start, end: points.end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    static func gradientPoints(angle: Double, in rect: CGRect) -> (start: CGPoint, end: CGPoint) {
        let radians = angle * .pi / 180
        let dx = cos(radians)
        let dy = sin(radians)
        let half = (abs(Double(rect.width) * dx) + abs(Double(rect.height) * dy)) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return (
            CGPoint(x: center.x - CGFloat(dx * half), y: center.y - CGFloat(dy * half)),
            CGPoint(x: center.x + CGFloat(dx * half), y: center.y + CGFloat(dy * half))
        )
    }

    // MARK: Lines

    static func drawLine(_ line: LineElement, offset: CGPoint, context: CGContext) {
        let start = CGPoint(x: line.start.x + offset.x, y: line.start.y + offset.y)
        let end = CGPoint(x: line.end.x + offset.x, y: line.end.y + offset.y)
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0.5 else { return }
        let width = CGFloat(line.stroke.width)
        let head = max(width * 3.2, 18)
        let direction = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
        // The shaft stops where an arrowhead begins, so its square end doesn't poke out of the point.
        let from = line.startArrow ? CGPoint(x: start.x + direction.x * head * 0.8, y: start.y + direction.y * head * 0.8) : start
        let to = line.endArrow ? CGPoint(x: end.x - direction.x * head * 0.8, y: end.y - direction.y * head * 0.8) : end
        context.saveGState()
        apply(line.stroke, context: context)
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
        context.setFillColor(line.stroke.color.cgColor)
        if line.endArrow { arrowhead(at: end, direction: direction, size: head, context: context) }
        if line.startArrow { arrowhead(at: start, direction: CGPoint(x: -direction.x, y: -direction.y), size: head, context: context) }
        context.restoreGState()
    }

    private static func arrowhead(at tip: CGPoint, direction: CGPoint, size: CGFloat, context: CGContext) {
        let back = CGPoint(x: tip.x - direction.x * size, y: tip.y - direction.y * size)
        let normal = CGPoint(x: -direction.y, y: direction.x)
        context.move(to: tip)
        context.addLine(to: CGPoint(x: back.x + normal.x * size * 0.55, y: back.y + normal.y * size * 0.55))
        context.addLine(to: CGPoint(x: back.x - normal.x * size * 0.55, y: back.y - normal.y * size * 0.55))
        context.closePath()
        context.fillPath()
    }

    // MARK: Images

    static func drawImageElement(_ element: ImageElement, in rect: CGRect, deck: UUID, context: CGContext, preview: Bool = false) {
        guard let image = SlideAssets.image(element.asset, deck: deck, preview: preview) else {
            // A missing file shows as a gray box rather than nothing.
            context.setFillColor(UIColor.systemGray4.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).cgColor)
            context.fill(rect)
            return
        }
        context.saveGState()
        if element.cornerRadius > 0 {
            context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: CGFloat(element.cornerRadius)).cgPath)
            context.clip()
        }
        drawImage(cropped(image, element.crop), in: rect, mode: element.mode, context: context)
        context.restoreGState()
    }

    static func cropped(_ image: UIImage, _ crop: CropInsets) -> UIImage {
        guard !crop.isEmpty, let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let area = CGRect(
            x: width * CGFloat(crop.left), y: height * CGFloat(crop.top),
            width: width * CGFloat(max(0.01, 1 - crop.left - crop.right)),
            height: height * CGFloat(max(0.01, 1 - crop.top - crop.bottom))
        ).integral
        guard let part = cgImage.cropping(to: area) else { return image }
        return UIImage(cgImage: part)
    }

    /// The image fitted inside the rect (letterboxed) or filling it (cut at the rect's edges).
    static func drawImage(_ image: UIImage, in rect: CGRect, mode: ImageFitMode, context: CGContext) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = mode == .fit
            ? min(rect.width / size.width, rect.height / size.height)
            : max(rect.width / size.width, rect.height / size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        let target = CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2, width: drawn.width, height: drawn.height)
        context.saveGState()
        context.clip(to: rect)
        image.draw(in: target)
        context.restoreGState()
    }

    // MARK: Tables

    static let cellInset: CGFloat = 14

    static func drawTable(_ table: TableElement, in rect: CGRect, context: CGContext) {
        for row in 0..<table.rows {
            for column in 0..<table.columns {
                let cellRect = table.cellRect(row: row, column: column, in: rect.size)
                let cell = table.cells[row][column]
                if let fill = cell.fill {
                    context.setFillColor(fill.cgColor)
                    context.fill(cellRect)
                }
                drawText(cell.text, in: cellRect, inset: cellInset)
            }
        }
        guard table.borderWidth > 0 else { return }
        context.saveGState()
        context.setStrokeColor(table.borderColor.cgColor)
        context.setLineWidth(CGFloat(table.borderWidth))
        context.stroke(rect)
        for row in 1..<max(table.rows, 1) {
            let y = table.cellRect(row: row, column: 0, in: rect.size).minY
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: rect.width, y: y))
        }
        for column in 1..<max(table.columns, 1) {
            let x = table.cellRect(row: 0, column: column, in: rect.size).minX
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: rect.height))
        }
        context.strokePath()
        context.restoreGState()
    }

    // MARK: Images of slides and elements

    /// The slide as a bitmap `width` points wide.
    static func image(of slide: SlideContent, deck: UUID, width: CGFloat, scale: CGFloat = 2, preview: Bool = true) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let factor = width / size.width
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: size.height * factor), format: format).image { context in
            context.cgContext.scaleBy(x: factor, y: factor)
            draw(slide, deck: deck, in: context.cgContext, preview: preview)
        }
    }

    /// One element alone on a transparent background (the PowerPoint export falls back to this), with its padding.
    static func image(of element: SlideElement, deck: UUID) -> UIImage {
        let frame = element.frame.cg
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let padding = padding(for: element)
        let size = CGSize(width: frame.width + padding * 2, height: frame.height + padding * 2)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: padding, y: padding)
            var unrotated = element
            unrotated.rotation = 0
            unrotated.opacity = 1
            drawContent(unrotated, deck: deck, in: context.cgContext)
        }
    }
}

/// The outlines of the shape kinds, fitted to a rect.
enum ShapePaths {
    static func path(_ kind: ShapeKind, in rect: CGRect, cornerRadius: CGFloat) -> CGPath {
        switch kind {
        case .rect:
            return CGPath(rect: rect, transform: nil)
        case .roundRect:
            let radius = min(max(cornerRadius, 0), min(rect.width, rect.height) / 2)
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        case .triangle:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        case .star:
            // A five-pointed star in a unit box, stretched to the rect.
            let path = CGMutablePath()
            let inner = 0.382
            for point in 0..<10 {
                let angle = Double(point) * .pi / 5 - .pi / 2
                let radius = point.isMultiple(of: 2) ? 0.5 : 0.5 * inner
                let x = rect.minX + CGFloat(0.5 + cos(angle) * radius) * rect.width
                let y = rect.minY + CGFloat(0.5 + sin(angle) * radius) * rect.height
                if point == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            path.closeSubpath()
            return path
        case .arrow:
            // Pointing right: a shaft half as tall as the box, and a head taking the last 40%.
            let path = CGMutablePath()
            let shaftTop = rect.minY + rect.height * 0.25
            let shaftBottom = rect.minY + rect.height * 0.75
            let headStart = rect.minX + rect.width * 0.6
            path.move(to: CGPoint(x: rect.minX, y: shaftTop))
            path.addLine(to: CGPoint(x: headStart, y: shaftTop))
            path.addLine(to: CGPoint(x: headStart, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: headStart, y: rect.maxY))
            path.addLine(to: CGPoint(x: headStart, y: shaftBottom))
            path.addLine(to: CGPoint(x: rect.minX, y: shaftBottom))
            path.closeSubpath()
            return path
        }
    }
}

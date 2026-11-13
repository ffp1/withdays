import SwiftUI
import UIKit

/// One element's content, drawn by `SlideRenderer` at the size it's shown, with room around it
/// for strokes, arrowheads and shadows. Position, rotation and opacity are applied by SwiftUI.
struct ElementRenderView: UIViewRepresentable {
    let element: SlideElement
    let deck: UUID
    let scale: CGFloat

    func makeUIView(context: Context) -> ElementDrawingView {
        let view = ElementDrawingView()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.contentMode = .redraw
        view.isUserInteractionEnabled = false
        return view
    }

    /// Shows empty text boxes' placeholders (the editor; the player leaves them out).
    var placeholders = false

    func updateUIView(_ view: ElementDrawingView, context: Context) {
        // Moving only changes where SwiftUI puts the view: the drawing stays as it is.
        let look = ElementDrawingView.Look(
            content: element.content, width: element.frame.width, height: element.frame.height,
            line: element.kind == .line ? element.frame.cg.origin : .zero, scale: scale, placeholders: placeholders
        )
        view.element = element
        view.deck = deck
        guard view.look != look else { return }
        view.look = look
        view.setNeedsDisplay()
    }
}

final class ElementDrawingView: UIView {
    struct Look: Equatable {
        let content: ElementContent
        let width: Double
        let height: Double
        /// A line's ends are absolute, so its drawing depends on where its box is.
        let line: CGPoint
        let scale: CGFloat
        let placeholders: Bool
    }

    var element: SlideElement?
    var deck = UUID()
    var look: Look?

    override func draw(_ rect: CGRect) {
        guard let element, let look, let context = UIGraphicsGetCurrentContext() else { return }
        context.scaleBy(x: look.scale, y: look.scale)
        let padding = SlideRenderer.padding(for: element)
        context.translateBy(x: padding, y: padding)
        SlideRenderer.drawContent(element, deck: deck, in: context, preview: true, placeholders: look.placeholders)
    }
}

/// The slide's background, drawn the same way as everywhere else.
struct SlideBackgroundView: UIViewRepresentable {
    let background: SlideBackground
    let deck: UUID

    func makeUIView(context: Context) -> BackgroundDrawingView {
        let view = BackgroundDrawingView()
        view.isOpaque = true
        view.contentMode = .redraw
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: BackgroundDrawingView, context: Context) {
        guard view.background != background || view.deck != deck else { return }
        view.background = background
        view.deck = deck
        view.setNeedsDisplay()
    }
}

final class BackgroundDrawingView: UIView {
    var background: SlideBackground = .solid(.white)
    var deck = UUID()

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), bounds.width > 0 else { return }
        let factor = bounds.width / SlideContent.size.width
        context.scaleBy(x: factor, y: factor)
        UIGraphicsPushContext(context)
        SlideRenderer.drawBackground(background, deck: deck, in: context, rect: CGRect(origin: .zero, size: SlideContent.size), preview: true)
        UIGraphicsPopContext()
    }
}

/// Thin lines over the slide at its middle (25 / 75 % fainter): never exported, never played.
struct GuidesOverlay: View {
    var body: some View {
        Canvas { context, size in
            for fraction in [0.25, 0.5, 0.75] {
                let strong = fraction == 0.5
                let color = Color(red: 0.008, green: 0.725, blue: 0.725).opacity(strong ? 0.8 : 0.4)
                let width: CGFloat = strong ? 1 : 0.5
                var vertical = Path()
                vertical.move(to: CGPoint(x: size.width * fraction, y: 0))
                vertical.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                context.stroke(vertical, with: .color(color), lineWidth: width)
                var horizontal = Path()
                horizontal.move(to: CGPoint(x: 0, y: size.height * fraction))
                horizontal.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                context.stroke(horizontal, with: .color(color), lineWidth: width)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

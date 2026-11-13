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

    func updateUIView(_ view: ElementDrawingView, context: Context) {
        guard view.element != element || view.deck != deck || view.scale != scale else { return }
        view.element = element
        view.deck = deck
        view.scale = scale
        view.setNeedsDisplay()
    }
}

final class ElementDrawingView: UIView {
    var element: SlideElement?
    var deck = UUID()
    var scale: CGFloat = 1

    override func draw(_ rect: CGRect) {
        guard let element, let context = UIGraphicsGetCurrentContext() else { return }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: SlideRenderer.padding, y: SlideRenderer.padding)
        SlideRenderer.drawContent(element, deck: deck, in: context)
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
        SlideRenderer.drawBackground(background, deck: deck, in: context, rect: CGRect(origin: .zero, size: SlideContent.size))
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

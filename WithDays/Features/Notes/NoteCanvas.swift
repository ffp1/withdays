import PDFKit
import PencilKit
import SwiftUI

/// Undo / redo for the page on screen, and saving it right away (before an export or leaving).
@MainActor
@Observable
final class NoteCanvasController {
    fileprivate(set) var canUndo = false
    fileprivate(set) var canRedo = false
    @ObservationIgnored fileprivate weak var canvas: PKCanvasView?
    @ObservationIgnored fileprivate var flushAction: (() -> Void)?

    func undo() {
        canvas?.undoManager?.undo()
        refresh()
    }

    func redo() {
        canvas?.undoManager?.redo()
        refresh()
    }

    func flush() {
        flushAction?()
    }

    fileprivate func refresh() {
        canUndo = canvas?.undoManager?.canUndo ?? false
        canRedo = canvas?.undoManager?.canRedo ?? false
    }
}

/// One page to write on with a finger: one finger draws, two fingers scroll and pinch to zoom,
/// and a two-finger sideways swipe on the whole page turns it.
struct NoteCanvas: UIViewRepresentable {
    let page: NotePage
    let pdf: PDFPage?
    let image: UIImage?
    let tool: any PKTool
    /// Changes when the tool or its settings do, so the canvas isn't given a tool in the middle of a stroke.
    let toolKey: String
    let controller: NoteCanvasController
    var load: () -> PKDrawing
    var save: (PKDrawing) -> Void
    /// +1 for the next page, -1 for the previous one.
    var onTurn: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> NotePageView {
        let view = NotePageView(page: page, pdf: pdf, image: image)
        let coordinator = context.coordinator
        coordinator.view = view
        coordinator.loading = true
        view.canvas.drawing = load()
        coordinator.loading = false
        view.canvas.tool = tool
        coordinator.toolKey = toolKey
        view.canvas.delegate = coordinator

        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.twoFingerPan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = coordinator
        view.addGestureRecognizer(pan)

        controller.canvas = view.canvas
        controller.flushAction = { [weak coordinator] in coordinator?.flush() }
        controller.refresh()
        return view
    }

    func updateUIView(_ view: NotePageView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.toolKey != toolKey {
            context.coordinator.toolKey = toolKey
            view.canvas.tool = tool
        }
        view.update(page: page)
    }

    static func dismantleUIView(_ view: NotePageView, coordinator: Coordinator) {
        coordinator.flush()
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var parent: NoteCanvas
        weak var view: NotePageView?
        var toolKey = ""
        var loading = false
        private var pending: DispatchWorkItem?

        init(_ parent: NoteCanvas) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !loading else { return }
            parent.controller.refresh()
            // Saved a moment after the last change, not on every point.
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.flush() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }

        func flush() {
            guard let pending, !pending.isCancelled, let canvas = view?.canvas else { return }
            pending.cancel()
            self.pending = nil
            parent.save(canvas.drawing)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            view?.place()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        /// Turns the page only when the whole page is showing; zoomed in, two fingers just move around.
        @objc func twoFingerPan(_ pan: UIPanGestureRecognizer) {
            guard pan.state == .ended, let view else { return }
            let canvas = view.canvas
            guard canvas.zoomScale <= canvas.minimumZoomScale * 1.03 else { return }
            let moved = pan.translation(in: view)
            guard abs(moved.x) > 60, abs(moved.x) > abs(moved.y) * 2 else { return }
            parent.onTurn(moved.x < 0 ? 1 : -1)
        }
    }
}

/// The PencilKit canvas with the paper under it. The canvas scrolls and zooms; the paper follows.
final class NotePageView: UIView {
    let canvas = PKCanvasView()
    private let paper: NotePaperView
    private var page: NotePage
    private var laidOut = CGSize.zero

    init(page: NotePage, pdf: PDFPage?, image: UIImage?) {
        self.page = page
        paper = NotePaperView(page: page, pdf: pdf, image: image)
        super.init(frame: .zero)

        canvas.drawingPolicy = .anyInput
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        // The paper is always white, so the ink keeps its colors in dark mode.
        canvas.overrideUserInterfaceStyle = .light
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.bouncesZoom = true
        addSubview(canvas)
        canvas.insertSubview(paper, at: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(page: NotePage) {
        guard page != self.page else { return }
        self.page = page
        paper.page = page
        paper.setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        guard bounds.size != laidOut, bounds.width > 0, bounds.height > 0 else { return }
        laidOut = bounds.size
        // The whole page fits, with a little room around it.
        let fit = min((bounds.width - 24) / page.size.width, (bounds.height - 24) / page.size.height)
        canvas.minimumZoomScale = fit
        canvas.maximumZoomScale = max(fit * 6, 3)
        canvas.contentSize = page.size
        canvas.zoomScale = fit
        place()
    }

    /// Keeps the drawable area the page's size at this zoom, centers it, and puts the paper under it.
    func place() {
        let zoom = canvas.zoomScale
        let size = CGSize(width: page.size.width * zoom, height: page.size.height * zoom)
        if abs(canvas.contentSize.width - size.width) > 0.5 || abs(canvas.contentSize.height - size.height) > 0.5 {
            canvas.contentSize = size
        }
        let horizontal = max(0, (bounds.width - size.width) / 2)
        let vertical = max(0, (bounds.height - size.height) / 2)
        canvas.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        paper.transform = CGAffineTransform(scaleX: zoom, y: zoom)
        paper.layer.position = .zero
    }
}

/// The paper, drawn in tiles so it stays sharp zoomed in without a huge bitmap.
final class NotePaperView: UIView {
    private final class Tiles: CATiledLayer {
        override class func fadeDuration() -> CFTimeInterval { 0 }
    }

    override class var layerClass: AnyClass { Tiles.self }

    var page: NotePage
    private let pdf: PDFPage?
    private let image: UIImage?

    init(page: NotePage, pdf: PDFPage?, image: UIImage?) {
        self.page = page
        self.pdf = pdf
        self.image = image
        super.init(frame: CGRect(origin: .zero, size: page.size))
        backgroundColor = .white
        isUserInteractionEnabled = false
        layer.anchorPoint = .zero
        layer.position = .zero
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)
        if let tiles = layer as? CATiledLayer {
            tiles.tileSize = CGSize(width: 512, height: 512)
            tiles.levelsOfDetail = 4
            tiles.levelsOfDetailBias = 3
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        NotePaperRenderer.draw(page, pdf: pdf, image: image, in: context)
    }
}

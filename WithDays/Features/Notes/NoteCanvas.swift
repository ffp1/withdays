import PDFKit
import PencilKit
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

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

extension NoteToolSettings {
    /// The PencilKit tool for the pen, highlighter, eraser and lasso; tape and text aren't PencilKit's.
    func pkTool(_ tool: NoteTool) -> (any PKTool)? {
        switch tool {
        case .pen: PKInkingTool(.pen, color: UIColor(notesHex: pen.color), width: pen.width)
        case .marker: PKInkingTool(.marker, color: UIColor(notesHex: marker.color), width: marker.width)
        case .eraser: eraserWhole ? PKEraserTool(.vector) : PKEraserTool(.bitmap, width: eraserWidth)
        case .lasso: PKLassoTool()
        case .tape, .text: nil
        }
    }
}

/// One page to write on with a finger: one finger draws, two fingers scroll and pinch to zoom,
/// and a two-finger sideways swipe on the whole page turns it.
struct NoteCanvas: UIViewRepresentable {
    let page: NotePage
    let pdf: PDFPage?
    let image: UIImage?
    let tool: NoteTool
    let settings: NoteToolSettings
    let controller: NoteCanvasController
    var load: () -> PKDrawing
    var save: (PKDrawing) -> Void
    var loadItems: () -> NoteItems
    var saveItems: (NoteItems) -> Void
    /// +1 for the next page, -1 for the previous one.
    var onTurn: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> NotePageView {
        let view = NotePageView(page: page, pdf: pdf, image: image, items: loadItems())
        let coordinator = context.coordinator
        coordinator.view = view
        coordinator.loading = true
        view.canvas.drawing = load()
        coordinator.loading = false
        view.canvas.delegate = coordinator
        view.overlay.onChange = { [weak coordinator] in coordinator?.parent.saveItems($0) }
        view.apply(tool: tool, settings: settings)
        coordinator.applied = Applied(tool: tool, settings: settings)

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
        // Only when something changed: the canvas mustn't be given a tool in the middle of a stroke.
        let applied = Applied(tool: tool, settings: settings)
        if context.coordinator.applied != applied {
            context.coordinator.applied = applied
            view.apply(tool: tool, settings: settings)
        }
        view.update(page: page)
    }

    static func dismantleUIView(_ view: NotePageView, coordinator: Coordinator) {
        coordinator.flush()
    }

    struct Applied: Equatable {
        let tool: NoteTool
        let settings: NoteToolSettings
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var parent: NoteCanvas
        weak var view: NotePageView?
        var applied: Applied?
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
            let work = DispatchWorkItem { [weak self] in self?.saveNow() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }

        private func saveNow() {
            guard pending != nil, let canvas = view?.canvas else { return }
            pending?.cancel()
            pending = nil
            parent.save(canvas.drawing)
        }

        /// Saves what's waiting and finishes any text being typed.
        func flush() {
            view?.overlay.endEditing()
            saveNow()
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

/// Follows one finger on the canvas without getting in PencilKit's way, for straightening a held stroke
/// and for the eraser to reach tapes and text boxes.
private final class NoteTouchTracker: UIGestureRecognizer {
    var onBegan: (CGPoint) -> Void = { _ in }
    var onMoved: (CGPoint) -> Void = { _ in }
    /// `true` when the finger was lifted, `false` when the touch was taken away (a second finger, a system gesture).
    var onEnded: (Bool) -> Void = { _ in }

    private weak var tracked: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // Two fingers scroll and zoom; that's not a stroke.
        if tracked != nil || (event.allTouches?.count ?? 1) > 1 {
            if tracked != nil {
                tracked = nil
                state = .cancelled
                onEnded(false)
            } else {
                state = .failed
            }
            return
        }
        guard let touch = touches.first else { return }
        tracked = touch
        state = .began
        onBegan(touch.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        state = .changed
        onMoved(tracked.location(in: view))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = tracked, touches.contains(touch) else { return }
        tracked = nil
        state = .ended
        onEnded(true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = tracked, touches.contains(touch) else { return }
        tracked = nil
        state = .cancelled
        onEnded(false)
    }

    override func reset() {
        tracked = nil
    }
}

/// The PencilKit canvas with the paper under it and the tapes / text boxes over it.
/// The canvas scrolls and zooms; the paper and the overlay follow.
final class NotePageView: UIView, UIGestureRecognizerDelegate {
    let canvas = PKCanvasView()
    let overlay: NoteOverlayView
    private let paper: NotePaperView
    private var page: NotePage
    private var laidOut = CGSize.zero
    private var keyboardInset: CGFloat = 0

    /// What a held stroke is straightened into; nil for tools that don't draw lines.
    private struct LineInk {
        let type: PKInkingTool.InkType
        let color: UIColor
        let width: CGFloat
    }

    private var lineInk: LineInk?
    private var erasesItems = false

    // One finger's stroke, as the tracker sees it (in page points).
    private var strokeStart: CGPoint?
    private var strokeEnd = CGPoint.zero
    private var strokeCount = 0
    private var travelled: CGFloat = 0
    private var holdAnchor = CGPoint.zero
    private var holdWork: DispatchWorkItem?
    private var straightening = false

    init(page: NotePage, pdf: PDFPage?, image: UIImage?, items: NoteItems) {
        self.page = page
        paper = NotePaperView(page: page, pdf: pdf, image: image)
        overlay = NoteOverlayView(pageSize: page.size, items: items)
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
        canvas.addSubview(overlay)

        overlay.onEditingFrame = { [weak self] frame in self?.reveal(frame) }

        let tracker = NoteTouchTracker()
        tracker.cancelsTouchesInView = false
        tracker.delaysTouchesBegan = false
        tracker.delaysTouchesEnded = false
        tracker.delegate = self
        tracker.onBegan = { [weak self] in self?.touchBegan($0) }
        tracker.onMoved = { [weak self] in self?.touchMoved($0) }
        tracker.onEnded = { [weak self] in self?.touchEnded(lifted: $0) }
        canvas.addGestureRecognizer(tracker)

        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func update(page: NotePage) {
        guard page != self.page else { return }
        self.page = page
        paper.page = page
        paper.setNeedsDisplay()
    }

    /// Hands the tool and its settings to the canvas and the overlay.
    func apply(tool: NoteTool, settings: NoteToolSettings) {
        if let pkTool = settings.pkTool(tool) { canvas.tool = pkTool }
        // Tape and text are placed on the overlay; a finger mustn't also draw under it.
        canvas.drawingGestureRecognizer.isEnabled = tool != .tape && tool != .text

        overlay.tapeWidth = settings.tape.width
        overlay.tapeColor = settings.tape.color
        overlay.textStyle = NoteTextStyle(
            size: settings.text.width, color: settings.text.color, bold: settings.textBold, background: settings.textBackground
        )
        overlay.mode = tool == .tape ? .tape : tool == .text ? .text : .none

        switch tool {
        case .pen:
            lineInk = LineInk(type: .pen, color: UIColor(notesHex: settings.pen.color), width: CGFloat(settings.pen.width))
        case .marker:
            lineInk = LineInk(type: .marker, color: UIColor(notesHex: settings.marker.color), width: CGFloat(settings.marker.width))
        default:
            lineInk = nil
        }
        erasesItems = tool == .eraser
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        guard bounds.size != laidOut, bounds.width > 0, bounds.height > 0 else { return }
        let first = laidOut == .zero
        laidOut = bounds.size
        // The whole page fits, with a little room around it.
        let fit = min((bounds.width - 24) / page.size.width, (bounds.height - 24) / page.size.height)
        canvas.minimumZoomScale = fit
        canvas.maximumZoomScale = max(fit * 6, 3)
        if first {
            canvas.contentSize = page.size
            canvas.zoomScale = fit
        } else if canvas.zoomScale < fit {
            canvas.zoomScale = fit
        }
        place()
    }

    /// Keeps the drawable area the page's size at this zoom, centers it, and puts the paper under it
    /// and the overlay over it.
    func place() {
        let zoom = canvas.zoomScale
        let size = CGSize(width: page.size.width * zoom, height: page.size.height * zoom)
        if abs(canvas.contentSize.width - size.width) > 0.5 || abs(canvas.contentSize.height - size.height) > 0.5 {
            canvas.contentSize = size
        }
        let horizontal = max(0, (bounds.width - size.width) / 2)
        let vertical = max(0, (bounds.height - size.height) / 2)
        canvas.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: max(vertical, keyboardInset), right: horizontal)
        paper.transform = CGAffineTransform(scaleX: zoom, y: zoom)
        paper.layer.position = .zero
        overlay.frame = CGRect(origin: .zero, size: size)
        overlay.zoom = zoom
        canvas.bringSubviewToFront(overlay)
    }

    // MARK: Keyboard

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let window, let end = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let mine = convert(bounds, to: window)
        keyboardInset = max(0, mine.maxY - end.minY)
        place()
        if let frame = overlay.editingFrame { reveal(frame) }
    }

    /// Scrolls so the text box being typed in is above the keyboard.
    private func reveal(_ frame: CGRect) {
        guard keyboardInset > 0 else { return }
        canvas.scrollRectToVisible(frame.insetBy(dx: 0, dy: -24), animated: true)
    }

    // MARK: One finger

    private func pagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / canvas.zoomScale, y: point.y / canvas.zoomScale)
    }

    private func touchBegan(_ point: CGPoint) {
        let start = pagePoint(point)
        if erasesItems { overlay.erase(at: start) }
        guard lineInk != nil else { return }
        strokeStart = start
        strokeEnd = start
        strokeCount = canvas.drawing.strokes.count
        travelled = 0
        holdAnchor = point
        straightening = false
        scheduleHold()
    }

    private func touchMoved(_ point: CGPoint) {
        let current = pagePoint(point)
        if erasesItems { overlay.erase(at: current) }
        guard let start = strokeStart, let ink = lineInk else { return }
        travelled += hypot(current.x - strokeEnd.x, current.y - strokeEnd.y)
        strokeEnd = current
        if straightening {
            overlay.showPreview(from: start, to: current, width: ink.width, color: previewColor(ink))
        } else if hypot(point.x - holdAnchor.x, point.y - holdAnchor.y) > 6 {
            // Still moving: the hold starts over from here.
            holdAnchor = point
            scheduleHold()
        }
    }

    private func touchEnded(lifted: Bool) {
        holdWork?.cancel()
        holdWork = nil
        guard let start = strokeStart else { return }
        strokeStart = nil
        guard straightening else { return }
        straightening = false
        overlay.hidePreview()
        guard lifted, let ink = lineInk else { return }
        commitLine(from: start, to: strokeEnd, ink: ink)
    }

    /// Keeping the finger still for half a second at the end of a stroke turns the stroke into a straight line.
    private func scheduleHold() {
        holdWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.beginStraightening() }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func beginStraightening() {
        guard let start = strokeStart, let ink = lineInk, !straightening, travelled > 12 else { return }
        straightening = true
        // Drops PencilKit's stroke in progress; from here the line follows the finger until it lifts.
        canvas.drawingGestureRecognizer.isEnabled = false
        canvas.drawingGestureRecognizer.isEnabled = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        overlay.showPreview(from: start, to: strokeEnd, width: ink.width, color: previewColor(ink))
    }

    private func previewColor(_ ink: LineInk) -> UIColor {
        ink.type == .marker ? ink.color.withAlphaComponent(0.45) : ink.color
    }

    private func commitLine(from start: CGPoint, to end: CGPoint, ink: LineInk) {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 1 else { return }
        let steps = max(2, Int(length / 4))
        let size = CGSize(width: ink.width, height: ink.width)
        var points: [PKStrokePoint] = []
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            points.append(PKStrokePoint(
                location: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t),
                timeOffset: TimeInterval(step) * 0.01, size: size, opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            ))
        }
        let stroke = PKStroke(ink: PKInk(ink.type, color: ink.color), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        // If the dropped stroke was kept after all, the line takes its place.
        var strokes = canvas.drawing.strokes
        if strokes.count > strokeCount { strokes = Array(strokes.prefix(strokeCount)) }
        strokes.append(stroke)
        setDrawing(PKDrawing(strokes: strokes))
    }

    /// Replaces the drawing in a way undo can take back.
    private func setDrawing(_ drawing: PKDrawing) {
        let old = canvas.drawing
        canvas.undoManager?.registerUndo(withTarget: self) { $0.setDrawing(old) }
        canvas.drawing = drawing
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

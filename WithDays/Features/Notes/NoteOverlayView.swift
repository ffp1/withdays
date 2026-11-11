import PencilKit
import UIKit

/// How new text boxes look, and what the box being edited is changed to.
struct NoteTextStyle: Equatable {
    var size: Double
    var color: Int
    var bold: Bool
    var background: Int?
    var font: String?
}

/// What was cut, to paste on this page or another.
struct NoteClip {
    var strokes: [PKStroke]
    var tapes: [NoteTape]
    var texts: [NoteText]
}

@MainActor
enum NoteClipboard {
    static var clip: NoteClip?
}

enum NoteSelectionAction {
    case cut, duplicate, delete, front, back
    case color(Int)
}

/// What the overlay needs from the page: the strokes, and marking a change so it can be undone as one step.
@MainActor
protocol NoteOverlayHost: AnyObject {
    var drawing: PKDrawing { get set }
    func beginChange()
    func endChange()
    /// Saves the tapes / text boxes without making it a step of undo.
    func itemsChangedQuietly()
    /// The middle of what's on screen, in page points.
    var visibleCenter: CGPoint { get }
}

/// The layer over the handwriting: masking tapes and text boxes, laid out at the canvas's zoom so they stay sharp,
/// and the selection (lasso, box, handles). It only takes touches while the tape, text or select tool is in use;
/// otherwise they fall through to the canvas.
final class NoteOverlayView: UIView, UITextViewDelegate, UIGestureRecognizerDelegate {
    enum Mode {
        case none, tape, text, select
    }

    struct Selection: Equatable {
        var strokes: Set<Int> = []
        var tapes: Set<String> = []
        var texts: Set<String> = []

        var isEmpty: Bool { strokes.isEmpty && tapes.isEmpty && texts.isEmpty }
    }

    /// The app's blue; fixed, as this layer is always in light colors.
    private static let accent = UIColor(notesHex: 0x065A8C)

    private let pageSize: CGSize
    private(set) var items: NoteItems
    weak var host: NoteOverlayHost?
    /// The box being typed in changed size or started; the canvas keeps it clear of the keyboard.
    var onEditingFrame: (CGRect) -> Void = { _ in }
    var onSelection: (Bool) -> Void = { _ in }

    var zoom: CGFloat = 1 {
        didSet { if zoom != oldValue { layoutItems() } }
    }

    var mode = Mode.none {
        didSet {
            guard mode != oldValue else { return }
            isUserInteractionEnabled = mode != .none
            if mode != .text { endEditing() }
            if mode != .select { clearSelection() }
        }
    }

    var tapeWidth = 22.0
    var tapeColor = 0xFFA94D
    var textStyle = NoteTextStyle(size: 16, color: 0x1C1C1E, bold: false, background: nil) {
        didSet { if textStyle != oldValue { restyleEditing() } }
    }

    private var tapeLayers: [String: CAShapeLayer] = [:]
    private var textViews: [String: UITextView] = [:]
    private let preview = CAShapeLayer()
    private let lassoLayer = CAShapeLayer()
    private let boxLayer = CAShapeLayer()
    private var cornerLayers: [CAShapeLayer] = []
    private let handle = UIView()
    private var editing: String?

    private(set) var selection = Selection() {
        didSet {
            if selection.isEmpty != oldValue.isEmpty { onSelection(!selection.isEmpty) }
            layoutSelection()
        }
    }

    private enum Drag {
        case tape(String)
        case move(String, CGPoint)
        case resize(String)
        case lasso
        case moveSelection(CGPoint)
        case scaleSelection(anchor: CGPoint, distance: CGFloat)
        /// One end of a single line or tape follows the finger; the other (`anchor`) stays.
        case stretchSelection(anchor: CGPoint, from: CGPoint)
    }

    private var drag: Drag?
    private var lassoPoints: [CGPoint] = []
    /// The strokes and items as they were when a selection drag began; each move works from these.
    private var dragStrokes: [PKStroke] = []
    private var dragItems = NoteItems()

    init(pageSize: CGSize, items: NoteItems) {
        self.pageSize = pageSize
        self.items = items
        super.init(frame: CGRect(origin: .zero, size: pageSize))
        backgroundColor = .clear
        isUserInteractionEnabled = false
        // Ink, tape and text keep their colors: the paper is always white.
        overrideUserInterfaceStyle = .light

        preview.fillColor = nil
        preview.lineCap = .round
        preview.lineJoin = .round
        preview.isHidden = true
        layer.addSublayer(preview)

        for dashed in [lassoLayer, boxLayer] {
            dashed.fillColor = nil
            dashed.strokeColor = Self.accent.cgColor
            dashed.lineWidth = 1.5
            dashed.lineDashPattern = [6, 4]
            dashed.isHidden = true
            layer.addSublayer(dashed)
        }
        for _ in 0..<4 {
            let corner = CAShapeLayer()
            corner.fillColor = UIColor.white.cgColor
            corner.strokeColor = Self.accent.cgColor
            corner.lineWidth = 2
            corner.path = UIBezierPath(ovalIn: CGRect(x: -6, y: -6, width: 12, height: 12)).cgPath
            corner.isHidden = true
            layer.addSublayer(corner)
            cornerLayers.append(corner)
        }

        handle.backgroundColor = .white
        handle.layer.borderColor = Self.accent.cgColor
        handle.layer.borderWidth = 2
        handle.layer.cornerRadius = 9
        handle.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
        handle.isUserInteractionEnabled = false
        handle.isHidden = true
        addSubview(handle)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        addGestureRecognizer(pan)

        layoutItems()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Undo / redo puts back a whole set of tapes and text boxes.
    func replace(_ items: NoteItems) {
        if let id = editing, let view = textViews[id] {
            editing = nil
            view.resignFirstResponder()
        }
        selection = Selection()
        self.items = items
        layoutItems()
    }

    // MARK: Layout

    /// Puts every tape and text box where it belongs at this zoom.
    private func layoutItems() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for (id, shape) in tapeLayers where !items.tapes.contains(where: { $0.id == id }) {
            shape.removeFromSuperlayer()
            tapeLayers[id] = nil
        }
        for (order, tape) in items.tapes.enumerated() {
            let shape = tapeLayers[tape.id] ?? {
                let shape = CAShapeLayer()
                shape.fillColor = nil
                shape.lineCap = .butt
                layer.insertSublayer(shape, below: preview)
                tapeLayers[tape.id] = shape
                return shape
            }()
            // Later tapes lie over earlier ones.
            shape.zPosition = CGFloat(order)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: CGFloat(tape.x1) * zoom, y: CGFloat(tape.y1) * zoom))
            path.addLine(to: CGPoint(x: CGFloat(tape.x2) * zoom, y: CGFloat(tape.y2) * zoom))
            shape.path = path.cgPath
            shape.lineWidth = CGFloat(tape.width) * zoom
            shape.strokeColor = UIColor(notesHex: tape.color).withAlphaComponent(tape.revealed ? 0.25 : 1).cgColor
        }
        for overlayLayer in [preview, lassoLayer, boxLayer] + cornerLayers {
            overlayLayer.zPosition = CGFloat(items.tapes.count + 1)
        }

        for (id, view) in textViews where !items.texts.contains(where: { $0.id == id }) {
            view.removeFromSuperview()
            textViews[id] = nil
        }
        for (order, text) in items.texts.enumerated() {
            let view = textViews[text.id] ?? {
                let view = UITextView()
                view.isScrollEnabled = false
                view.textContainer.lineFragmentPadding = 0
                view.delegate = self
                view.isEditable = false
                view.isSelectable = false
                view.isUserInteractionEnabled = false
                view.layer.borderColor = Self.accent.cgColor
                addSubview(view)
                textViews[text.id] = view
                return view
            }()
            // Text boxes sit under the tapes (so a tape can hide them), later boxes over earlier ones.
            view.layer.zPosition = CGFloat(order) - CGFloat(items.texts.count) - 1
            if view.text != text.text { view.text = text.text }
            view.font = NoteFont.font(text.font, size: CGFloat(text.size) * zoom, bold: text.bold)
            view.textColor = UIColor(notesHex: text.color)
            view.backgroundColor = text.background.map { UIColor(notesHex: $0) } ?? .clear
            view.layer.cornerRadius = 4 * zoom
            let inset = NoteText.inset * zoom
            view.textContainerInset = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
            let width = CGFloat(text.width) * zoom
            let height = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            view.frame = CGRect(x: CGFloat(text.x) * zoom, y: CGFloat(text.y) * zoom, width: width, height: height)
            view.layer.borderWidth = text.id == editing ? 1 : 0
        }

        if let editing, let view = textViews[editing] {
            handle.isHidden = false
            handle.center = CGPoint(x: view.frame.maxX + 14, y: view.frame.midY)
            handle.layer.zPosition = CGFloat(items.tapes.count + 2)
        } else {
            handle.isHidden = true
        }
        layoutSelection()
    }

    /// The dashed box around what's selected, with a handle on each corner.
    private func layoutSelection() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let bounds = selectionBounds else {
            boxLayer.isHidden = true
            cornerLayers.forEach { $0.isHidden = true }
            return
        }
        let box = CGRect(x: bounds.minX * zoom, y: bounds.minY * zoom, width: bounds.width * zoom, height: bounds.height * zoom)
            .insetBy(dx: -6, dy: -6)
        boxLayer.path = UIBezierPath(rect: box).cgPath
        boxLayer.isHidden = false
        // A single line or tape is shaped by its two ends; anything else by the box's corners.
        let points: [CGPoint]
        if let ends = selectionEnds {
            points = [ends.0, ends.1].map { CGPoint(x: $0.x * zoom, y: $0.y * zoom) }
        } else {
            points = [
                CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY),
            ]
        }
        for (index, corner) in cornerLayers.enumerated() {
            corner.isHidden = index >= points.count
            if index < points.count { corner.position = points[index] }
        }
    }

    /// The two ends of the one stroke or tape that's selected, in page points; nil for any other selection.
    private var selectionEnds: (CGPoint, CGPoint)? {
        guard selection.texts.isEmpty, selection.strokes.count + selection.tapes.count == 1 else { return nil }
        if let id = selection.tapes.first, let tape = items.tapes.first(where: { $0.id == id }) {
            return (CGPoint(x: tape.x1, y: tape.y1), CGPoint(x: tape.x2, y: tape.y2))
        }
        guard let index = selection.strokes.first, let strokes = host?.drawing.strokes, strokes.indices.contains(index) else { return nil }
        let stroke = strokes[index]
        guard let first = stroke.path.first, let last = stroke.path.last else { return nil }
        let start = first.location.applying(stroke.transform)
        let end = last.location.applying(stroke.transform)
        // A closed shape (or a dot) has no ends to pull.
        guard hypot(end.x - start.x, end.y - start.y) > 12 else { return nil }
        return (start, end)
    }

    /// The box being typed in, in this view's coordinates.
    var editingFrame: CGRect? {
        editing.flatMap { textViews[$0]?.frame }
    }

    // MARK: Line preview (drawn by the canvas while a held stroke is being straightened)

    func showPreview(_ points: [CGPoint], width: CGFloat, color: UIColor) {
        guard let first = points.first else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: first.x * zoom, y: first.y * zoom))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * zoom, y: point.y * zoom))
        }
        preview.path = path.cgPath
        preview.lineWidth = width * zoom
        preview.strokeColor = color.cgColor
        preview.isHidden = false
        CATransaction.commit()
    }

    func hidePreview() {
        preview.isHidden = true
    }

    // MARK: Erasing

    /// The eraser passing over a tape or a text box removes it. The caller marks the change.
    func erase(at point: CGPoint) {
        let tapes = items.tapes.filter { !Self.hit($0, point, slack: 4) }
        let texts = items.texts.filter { !(textFrame($0.id)?.contains(point) ?? false) }
        guard tapes.count != items.tapes.count || texts.count != items.texts.count else { return }
        items.tapes = tapes
        items.texts = texts
        layoutItems()
    }

    private static func hit(_ tape: NoteTape, _ point: CGPoint, slack: CGFloat) -> Bool {
        let a = CGPoint(x: tape.x1, y: tape.y1)
        let b = CGPoint(x: tape.x2, y: tape.y2)
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = dx * dx + dy * dy
        guard length > 0 else { return false }
        // Past the ends doesn't count: tape has square ends.
        let t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / length
        guard t >= 0, t <= 1 else { return false }
        let distance = abs((point.x - a.x) * dy - (point.y - a.y) * dx) / sqrt(length)
        return distance <= CGFloat(tape.width) / 2 + slack
    }

    // MARK: Geometry (page points)

    private func pagePoint(_ recognizer: UIGestureRecognizer) -> CGPoint {
        let point = recognizer.location(in: self)
        return CGPoint(x: point.x / zoom, y: point.y / zoom)
    }

    /// Where the finger first touched: a pan is only recognized after it has moved a little.
    private func pageOrigin(_ recognizer: UIPanGestureRecognizer) -> CGPoint {
        let point = recognizer.location(in: self)
        let moved = recognizer.translation(in: self)
        return CGPoint(x: (point.x - moved.x) / zoom, y: (point.y - moved.y) / zoom)
    }

    private func textFrame(_ id: String) -> CGRect? {
        guard let frame = textViews[id]?.frame else { return nil }
        return CGRect(x: frame.minX / zoom, y: frame.minY / zoom, width: frame.width / zoom, height: frame.height / zoom)
    }

    private func text(at point: CGPoint) -> NoteText? {
        items.texts.last { textFrame($0.id)?.contains(point) ?? false }
    }

    private static func bounds(of tape: NoteTape) -> CGRect {
        let half = CGFloat(tape.width) / 2
        return CGRect(
            x: CGFloat(min(tape.x1, tape.x2)), y: CGFloat(min(tape.y1, tape.y2)),
            width: CGFloat(abs(tape.x2 - tape.x1)), height: CGFloat(abs(tape.y2 - tape.y1))
        ).insetBy(dx: -half, dy: -half)
    }

    private var selectionBounds: CGRect? {
        guard !selection.isEmpty else { return nil }
        var rects: [CGRect] = []
        if let strokes = host?.drawing.strokes {
            for index in selection.strokes where strokes.indices.contains(index) {
                rects.append(strokes[index].renderBounds)
            }
        }
        for tape in items.tapes where selection.tapes.contains(tape.id) {
            rects.append(Self.bounds(of: tape))
        }
        for id in selection.texts {
            if let frame = textFrame(id) { rects.append(frame) }
        }
        guard var union = rects.first else { return nil }
        for rect in rects.dropFirst() { union = union.union(rect) }
        return union
    }

    private static func points(of stroke: PKStroke, every distance: CGFloat) -> [CGPoint] {
        stroke.path.interpolatedPoints(by: .distance(distance)).map { $0.location.applying(stroke.transform) }
    }

    private static func contains(_ polygon: [CGPoint], _ point: CGPoint) -> Bool {
        guard polygon.count > 2 else { return false }
        var inside = false
        var previous = polygon[polygon.count - 1]
        for current in polygon {
            if (current.y > point.y) != (previous.y > point.y),
               point.x < (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x {
                inside.toggle()
            }
            previous = current
        }
        return inside
    }

    // MARK: Gestures

    /// Typing and selecting inside the box being edited is the text view's business.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view, current !== self {
            if current is UITextView { return false }
            view = current.superview
        }
        return true
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        let point = pagePoint(recognizer)
        switch mode {
        case .none:
            break
        case .tape:
            // Peel back / put back the topmost tape here.
            guard let index = items.tapes.lastIndex(where: { Self.hit($0, point, slack: 2) }) else { return }
            items.tapes[index].revealed.toggle()
            UISelectionFeedbackGenerator().selectionChanged()
            layoutItems()
            host?.itemsChangedQuietly()
        case .text:
            if editing != nil {
                endEditing()
            } else if let text = text(at: point) {
                host?.beginChange()
                beginEditing(text.id)
            } else {
                let x = Double(min(max(point.x, 8), pageSize.width - 88))
                let width = max(80, min(240, Double(pageSize.width) - x - 8))
                let y = max(4, Double(point.y) - textStyle.size * 0.8)
                let text = NoteText(
                    id: NotesData.newID("text"), x: x, y: y, width: width, text: "",
                    size: textStyle.size, color: textStyle.color, bold: textStyle.bold, background: textStyle.background,
                    font: textStyle.font
                )
                host?.beginChange()
                items.texts.append(text)
                layoutItems()
                beginEditing(text.id)
            }
        case .select:
            selection = single(at: point)
        }
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        let point = pagePoint(recognizer)
        switch recognizer.state {
        case .began:
            drag = nil
            let origin = pageOrigin(recognizer)
            switch mode {
            case .none:
                break
            case .tape:
                let id = NotesData.newID("tape")
                host?.beginChange()
                items.tapes.append(NoteTape(
                    id: id, x1: Double(origin.x), y1: Double(origin.y), x2: Double(point.x), y2: Double(point.y),
                    width: tapeWidth, color: tapeColor, revealed: false
                ))
                drag = .tape(id)
                layoutItems()
            case .text:
                let touch = CGPoint(x: origin.x * zoom, y: origin.y * zoom)
                if let editing, !handle.isHidden, hypot(touch.x - handle.center.x, touch.y - handle.center.y) < 24 {
                    drag = .resize(editing)
                } else if let text = text(at: origin) {
                    // Any box can be dragged, typed-in or not; typing in another one ends first.
                    if let editing, editing != text.id { endEditing() }
                    if editing == nil { host?.beginChange() }
                    drag = .move(text.id, CGPoint(x: origin.x - CGFloat(text.x), y: origin.y - CGFloat(text.y)))
                }
            case .select:
                beginSelectionDrag(at: origin)
                if case .lasso = drag { lassoPoints.append(point) }
            }
        case .changed:
            switch drag {
            case .tape(let id):
                guard let index = items.tapes.firstIndex(where: { $0.id == id }) else { return }
                items.tapes[index].x2 = Double(point.x)
                items.tapes[index].y2 = Double(point.y)
                layoutItems()
            case .move(let id, let offset):
                guard let index = items.texts.firstIndex(where: { $0.id == id }) else { return }
                items.texts[index].x = Double(min(max(point.x - offset.x, 0), pageSize.width - 20))
                items.texts[index].y = Double(min(max(point.y - offset.y, 0), pageSize.height - 20))
                layoutItems()
            case .resize(let id):
                guard let index = items.texts.firstIndex(where: { $0.id == id }) else { return }
                // The handle sits a little right of the box's edge.
                items.texts[index].width = max(60, Double(point.x - 14 / zoom) - items.texts[index].x)
                layoutItems()
            case .lasso:
                lassoPoints.append(point)
                showLasso()
            case .moveSelection(let start):
                transformSelection(CGAffineTransform(translationX: point.x - start.x, y: point.y - start.y), scale: 1)
            case .stretchSelection(let anchor, let from):
                let before = hypot(from.x - anchor.x, from.y - anchor.y)
                let after = hypot(point.x - anchor.x, point.y - anchor.y)
                guard before > 1, after > 4 else { return }
                // Turns and scales about the other end, so this end lands under the finger.
                let angle = atan2(point.y - anchor.y, point.x - anchor.x) - atan2(from.y - anchor.y, from.x - anchor.x)
                let transform = CGAffineTransform(translationX: anchor.x, y: anchor.y)
                    .rotated(by: angle)
                    .scaledBy(x: after / before, y: after / before)
                    .translatedBy(x: -anchor.x, y: -anchor.y)
                // A tape keeps its width; a stroke's width follows its length.
                transformSelection(transform, scale: 1)
            case .scaleSelection(let anchor, let distance):
                let scale = min(max(hypot(point.x - anchor.x, point.y - anchor.y) / distance, 0.2), 6)
                let transform = CGAffineTransform(translationX: anchor.x, y: anchor.y)
                    .scaledBy(x: scale, y: scale)
                    .translatedBy(x: -anchor.x, y: -anchor.y)
                transformSelection(transform, scale: scale)
            case nil:
                return
            }
        case .ended, .cancelled, .failed:
            guard let finished = drag else { return }
            drag = nil
            switch finished {
            case .tape(let id):
                if let index = items.tapes.firstIndex(where: { $0.id == id }) {
                    let tape = items.tapes[index]
                    // A touch that barely moved isn't a tape.
                    if hypot(tape.x2 - tape.x1, tape.y2 - tape.y1) < 8 { items.tapes.remove(at: index) }
                }
                layoutItems()
                host?.endChange()
            case .move, .resize:
                layoutItems()
                // While typing, the change ends with the typing.
                if editing == nil { host?.endChange() }
            case .lasso:
                lassoLayer.isHidden = true
                selection = enclosed(by: lassoPoints)
                lassoPoints = []
            case .moveSelection, .scaleSelection, .stretchSelection:
                dragStrokes = []
                host?.endChange()
            }
        default:
            break
        }
    }

    // MARK: Text editing

    /// The caller has marked the change's start; it ends when the typing does.
    private func beginEditing(_ id: String) {
        guard let view = textViews[id] else { return }
        editing = id
        view.isEditable = true
        view.isSelectable = true
        view.isUserInteractionEnabled = true
        layoutItems()
        view.becomeFirstResponder()
        onEditingFrame(view.frame)
    }

    /// Stops typing and saves; a box left empty goes away.
    func endEditing() {
        guard let id = editing else { return }
        editing = nil
        if let view = textViews[id] {
            view.resignFirstResponder()
            view.isEditable = false
            view.isSelectable = false
            view.isUserInteractionEnabled = false
        }
        if let index = items.texts.firstIndex(where: { $0.id == id }),
           items.texts[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.texts.remove(at: index)
        }
        layoutItems()
        host?.endChange()
    }

    /// The options changed while a box is being edited: it takes them on.
    private func restyleEditing() {
        guard let id = editing, let index = items.texts.firstIndex(where: { $0.id == id }) else { return }
        items.texts[index].size = textStyle.size
        items.texts[index].color = textStyle.color
        items.texts[index].bold = textStyle.bold
        items.texts[index].background = textStyle.background
        items.texts[index].font = textStyle.font
        layoutItems()
    }

    func textViewDidChange(_ textView: UITextView) {
        guard let id = editing, let index = items.texts.firstIndex(where: { $0.id == id }) else { return }
        items.texts[index].text = textView.text
        layoutItems()
        onEditingFrame(textView.frame)
    }

    // MARK: Selecting

    func clearSelection() {
        lassoLayer.isHidden = true
        if !selection.isEmpty { selection = Selection() }
    }

    /// The topmost thing under a tap: a tape, a text box, or a stroke.
    private func single(at point: CGPoint) -> Selection {
        if let tape = items.tapes.last(where: { Self.hit($0, point, slack: 2) }) {
            return Selection(tapes: [tape.id])
        }
        if let text = text(at: point) {
            return Selection(texts: [text.id])
        }
        let strokes = host?.drawing.strokes ?? []
        for index in strokes.indices.reversed() {
            let stroke = strokes[index]
            guard stroke.renderBounds.insetBy(dx: -12, dy: -12).contains(point) else { continue }
            let reach = max(10, (stroke.path.first?.size.width ?? 4) / 2 + 6)
            if Self.points(of: stroke, every: 5).contains(where: { hypot($0.x - point.x, $0.y - point.y) <= reach }) {
                return Selection(strokes: [index])
            }
        }
        return Selection()
    }

    /// What the lasso went around: strokes mostly inside it, tapes and text boxes whose middle is inside.
    private func enclosed(by polygon: [CGPoint]) -> Selection {
        var found = Selection()
        guard polygon.count > 2 else { return found }
        let strokes = host?.drawing.strokes ?? []
        for (index, stroke) in strokes.enumerated() {
            let points = Self.points(of: stroke, every: 8)
            guard !points.isEmpty else { continue }
            let inside = points.filter { Self.contains(polygon, $0) }.count
            if Double(inside) >= Double(points.count) * 0.6 { found.strokes.insert(index) }
        }
        for tape in items.tapes {
            let middle = CGPoint(x: (tape.x1 + tape.x2) / 2, y: (tape.y1 + tape.y2) / 2)
            if Self.contains(polygon, middle) { found.tapes.insert(tape.id) }
        }
        for text in items.texts {
            if let frame = textFrame(text.id), Self.contains(polygon, CGPoint(x: frame.midX, y: frame.midY)) {
                found.texts.insert(text.id)
            }
        }
        return found
    }

    private func showLasso() {
        guard let first = lassoPoints.first else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: first.x * zoom, y: first.y * zoom))
        for point in lassoPoints.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * zoom, y: point.y * zoom))
        }
        lassoLayer.path = path.cgPath
        lassoLayer.isHidden = false
        CATransaction.commit()
    }

    /// A corner handle scales, inside the box moves, anywhere else starts a new lasso.
    private func beginSelectionDrag(at point: CGPoint) {
        if let bounds = selectionBounds {
            let box = bounds.insetBy(dx: -6 / zoom, dy: -6 / zoom)
            let corners = [
                CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY),
            ]
            let reach = 24 / zoom
            if let ends = selectionEnds {
                // A single line or tape: pull an end; the other stays put.
                let fromStart = hypot(ends.0.x - point.x, ends.0.y - point.y)
                let fromEnd = hypot(ends.1.x - point.x, ends.1.y - point.y)
                if min(fromStart, fromEnd) < reach {
                    startSelectionChange()
                    drag = fromStart < fromEnd
                        ? .stretchSelection(anchor: ends.1, from: ends.0)
                        : .stretchSelection(anchor: ends.0, from: ends.1)
                    return
                }
            } else if let corner = corners.firstIndex(where: { hypot($0.x - point.x, $0.y - point.y) < reach }) {
                // Scales from the opposite corner.
                let anchor = corners[3 - corner]
                let distance = hypot(point.x - anchor.x, point.y - anchor.y)
                if distance > 4 {
                    startSelectionChange()
                    drag = .scaleSelection(anchor: anchor, distance: distance)
                    return
                }
            }
            if box.contains(point) {
                startSelectionChange()
                drag = .moveSelection(point)
                return
            }
        }
        clearSelection()
        lassoPoints = [point]
        drag = .lasso
    }

    private func startSelectionChange() {
        host?.beginChange()
        dragStrokes = host?.drawing.strokes ?? []
        dragItems = items
    }

    /// Moves or scales what's selected, from how it was when the drag began.
    private func transformSelection(_ transform: CGAffineTransform, scale: CGFloat) {
        var strokes = dragStrokes
        for index in selection.strokes where strokes.indices.contains(index) {
            strokes[index].transform = dragStrokes[index].transform.concatenating(transform)
        }
        if !selection.strokes.isEmpty { host?.drawing = PKDrawing(strokes: strokes) }
        var changed = dragItems
        for index in changed.tapes.indices where selection.tapes.contains(changed.tapes[index].id) {
            Self.apply(transform, scale: scale, to: &changed.tapes[index])
        }
        for index in changed.texts.indices where selection.texts.contains(changed.texts[index].id) {
            Self.apply(transform, scale: scale, to: &changed.texts[index])
        }
        items = changed
        layoutItems()
    }

    private static func apply(_ transform: CGAffineTransform, scale: CGFloat, to tape: inout NoteTape) {
        let start = CGPoint(x: tape.x1, y: tape.y1).applying(transform)
        let end = CGPoint(x: tape.x2, y: tape.y2).applying(transform)
        tape.x1 = Double(start.x)
        tape.y1 = Double(start.y)
        tape.x2 = Double(end.x)
        tape.y2 = Double(end.y)
        tape.width *= Double(scale)
    }

    private static func apply(_ transform: CGAffineTransform, scale: CGFloat, to text: inout NoteText) {
        let origin = CGPoint(x: text.x, y: text.y).applying(transform)
        text.x = Double(origin.x)
        text.y = Double(origin.y)
        text.width *= Double(scale)
        text.size *= Double(scale)
    }

    // MARK: Selection actions

    func perform(_ action: NoteSelectionAction) {
        guard !selection.isEmpty, let host else { return }
        var strokes = host.drawing.strokes
        let picked = selection.strokes.filter { strokes.indices.contains($0) }.sorted()
        host.beginChange()
        defer { host.endChange() }

        switch action {
        case .cut, .delete:
            if case .cut = action {
                NoteClipboard.clip = NoteClip(
                    strokes: picked.map { strokes[$0] },
                    tapes: items.tapes.filter { selection.tapes.contains($0.id) },
                    texts: items.texts.filter { selection.texts.contains($0.id) }
                )
            }
            let removed = selection
            selection = Selection()
            for index in picked.reversed() { strokes.remove(at: index) }
            if !picked.isEmpty { host.drawing = PKDrawing(strokes: strokes) }
            items.tapes.removeAll { removed.tapes.contains($0.id) }
            items.texts.removeAll { removed.texts.contains($0.id) }
            layoutItems()
        case .duplicate:
            let clip = NoteClip(
                strokes: picked.map { strokes[$0] },
                tapes: items.tapes.filter { selection.tapes.contains($0.id) },
                texts: items.texts.filter { selection.texts.contains($0.id) }
            )
            add(clip, moved: CGAffineTransform(translationX: 16, y: 16))
        case .front, .back:
            let toFront: Bool = { if case .front = action { return true } else { return false } }()
            if !picked.isEmpty {
                let chosen = picked.map { strokes[$0] }
                let rest = strokes.indices.filter { !selection.strokes.contains($0) }.map { strokes[$0] }
                host.drawing = PKDrawing(strokes: toFront ? rest + chosen : chosen + rest)
                let range = toFront ? rest.count..<(rest.count + chosen.count) : 0..<chosen.count
                selection.strokes = Set(range)
            }
            let tapes = items.tapes.filter { selection.tapes.contains($0.id) }
            let otherTapes = items.tapes.filter { !selection.tapes.contains($0.id) }
            items.tapes = toFront ? otherTapes + tapes : tapes + otherTapes
            let texts = items.texts.filter { selection.texts.contains($0.id) }
            let otherTexts = items.texts.filter { !selection.texts.contains($0.id) }
            items.texts = toFront ? otherTexts + texts : texts + otherTexts
            layoutItems()
        case .color(let hex):
            let color = UIColor(notesHex: hex)
            for index in picked {
                strokes[index].ink = PKInk(strokes[index].ink.inkType, color: color)
            }
            if !picked.isEmpty { host.drawing = PKDrawing(strokes: strokes) }
            for index in items.tapes.indices where selection.tapes.contains(items.tapes[index].id) {
                items.tapes[index].color = hex
            }
            for index in items.texts.indices where selection.texts.contains(items.texts[index].id) {
                items.texts[index].color = hex
            }
            layoutItems()
        }
    }

    /// Puts what was cut in the middle of what's on screen, selected.
    func paste() {
        guard let clip = NoteClipboard.clip, let host else { return }
        var rects = clip.strokes.map(\.renderBounds) + clip.tapes.map { Self.bounds(of: $0) }
        rects += clip.texts.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.size * 1.4) }
        guard var union = rects.first else { return }
        for rect in rects.dropFirst() { union = union.union(rect) }
        let center = host.visibleCenter
        host.beginChange()
        add(clip, moved: CGAffineTransform(translationX: center.x - union.midX, y: center.y - union.midY))
        host.endChange()
    }

    /// Adds copies on top and selects them. The caller marks the change.
    private func add(_ clip: NoteClip, moved transform: CGAffineTransform) {
        guard let host else { return }
        var strokes = host.drawing.strokes
        let first = strokes.count
        for var stroke in clip.strokes {
            stroke.transform = stroke.transform.concatenating(transform)
            strokes.append(stroke)
        }
        if !clip.strokes.isEmpty { host.drawing = PKDrawing(strokes: strokes) }
        var added = Selection(strokes: Set(first..<strokes.count))
        for var tape in clip.tapes {
            tape.id = NotesData.newID("tape")
            Self.apply(transform, scale: 1, to: &tape)
            items.tapes.append(tape)
            added.tapes.insert(tape.id)
        }
        for var text in clip.texts {
            text.id = NotesData.newID("text")
            Self.apply(transform, scale: 1, to: &text)
            items.texts.append(text)
            added.texts.insert(text.id)
        }
        layoutItems()
        selection = added
    }

    /// The selected strokes alone on white, for reading them as text; nil when no stroke is selected.
    func selectedStrokesImage() -> (image: UIImage, bounds: CGRect)? {
        guard let host else { return nil }
        let strokes = host.drawing.strokes
        let picked = selection.strokes.filter { strokes.indices.contains($0) }.sorted().map { strokes[$0] }
        guard var bounds = picked.first?.renderBounds else { return nil }
        for stroke in picked.dropFirst() { bounds = bounds.union(stroke.renderBounds) }
        let frame = bounds.insetBy(dx: -12, dy: -12)
        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = PKDrawing(strokes: picked).image(from: frame, scale: 3)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: frame.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: frame.size))
            ink.draw(in: CGRect(origin: .zero, size: frame.size))
        }
        return (image, bounds)
    }

    /// Swaps the selected strokes for a text box with what they say.
    func replaceSelectedStrokes(with string: String, in bounds: CGRect) {
        guard let host else { return }
        var strokes = host.drawing.strokes
        let picked = selection.strokes.filter { strokes.indices.contains($0) }.sorted()
        guard !picked.isEmpty else { return }
        let lines = max(1, string.components(separatedBy: "\n").count)
        let size = min(max(Double(bounds.height) / Double(lines) * 0.7, 10), 40)
        // The text takes the color most of the handwriting was in.
        var counts: [Int: Int] = [:]
        for index in picked { counts[strokes[index].ink.color.notesHex, default: 0] += 1 }
        let color = counts.max { $0.value < $1.value }?.key ?? textStyle.color
        host.beginChange()
        selection = Selection()
        for index in picked.reversed() { strokes.remove(at: index) }
        host.drawing = PKDrawing(strokes: strokes)
        let text = NoteText(
            id: NotesData.newID("text"), x: Double(bounds.minX), y: Double(bounds.minY),
            width: max(80, Double(bounds.width) + 16), text: string,
            size: size, color: color, bold: false, background: nil, font: textStyle.font
        )
        items.texts.append(text)
        layoutItems()
        selection = Selection(texts: [text.id])
        host.endChange()
    }
}

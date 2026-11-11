import UIKit

/// How new text boxes look, and what the box being edited is changed to.
struct NoteTextStyle: Equatable {
    var size: Double
    var color: Int
    var bold: Bool
    var background: Int?
}

/// The layer over the handwriting: masking tapes and text boxes, laid out at the canvas's zoom so they stay sharp.
/// It only takes touches while the tape or text tool is in use; otherwise they fall through to the canvas.
final class NoteOverlayView: UIView, UITextViewDelegate, UIGestureRecognizerDelegate {
    enum Mode {
        case none, tape, text
    }

    /// The app's blue; fixed, as this layer is always in light colors.
    private static let accent = UIColor(notesHex: 0x065A8C)

    private let pageSize: CGSize
    private(set) var items: NoteItems
    var onChange: (NoteItems) -> Void = { _ in }
    /// The box being typed in changed size or started; the canvas keeps it clear of the keyboard.
    var onEditingFrame: (CGRect) -> Void = { _ in }

    var zoom: CGFloat = 1 {
        didSet { if zoom != oldValue { layoutItems() } }
    }

    var mode = Mode.none {
        didSet {
            guard mode != oldValue else { return }
            isUserInteractionEnabled = mode != .none
            if mode != .text { endEditing() }
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
    private let handle = UIView()
    private var editing: String?

    private enum Drag {
        case tape(String)
        case move(String, CGPoint)
        case resize(String)
    }

    private var drag: Drag?

    init(pageSize: CGSize, items: NoteItems) {
        self.pageSize = pageSize
        self.items = items
        super.init(frame: CGRect(origin: .zero, size: pageSize))
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true
        // Ink, tape and text keep their colors: the paper is always white.
        overrideUserInterfaceStyle = .light

        preview.fillColor = nil
        preview.lineCap = .round
        preview.isHidden = true
        layer.addSublayer(preview)

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
        for tape in items.tapes {
            let shape = tapeLayers[tape.id] ?? {
                let shape = CAShapeLayer()
                shape.fillColor = nil
                shape.lineCap = .butt
                layer.insertSublayer(shape, below: preview)
                tapeLayers[tape.id] = shape
                return shape
            }()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: CGFloat(tape.x1) * zoom, y: CGFloat(tape.y1) * zoom))
            path.addLine(to: CGPoint(x: CGFloat(tape.x2) * zoom, y: CGFloat(tape.y2) * zoom))
            shape.path = path.cgPath
            shape.lineWidth = CGFloat(tape.width) * zoom
            shape.strokeColor = UIColor(notesHex: tape.color).withAlphaComponent(tape.revealed ? 0.25 : 1).cgColor
        }

        for (id, view) in textViews where !items.texts.contains(where: { $0.id == id }) {
            view.removeFromSuperview()
            textViews[id] = nil
        }
        for text in items.texts {
            let view = textViews[text.id] ?? {
                let view = UITextView()
                view.isScrollEnabled = false
                view.textContainer.lineFragmentPadding = 0
                view.delegate = self
                view.isEditable = false
                view.isSelectable = false
                view.isUserInteractionEnabled = false
                view.layer.borderColor = Self.accent.cgColor
                // Text boxes sit under the tapes, so a tape can hide them.
                insertSubview(view, at: 0)
                textViews[text.id] = view
                return view
            }()
            if view.text != text.text { view.text = text.text }
            view.font = .systemFont(ofSize: CGFloat(text.size) * zoom, weight: text.bold ? .bold : .regular)
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
            bringSubviewToFront(handle)
        } else {
            handle.isHidden = true
        }
    }

    /// The box being typed in, in this view's coordinates.
    var editingFrame: CGRect? {
        editing.flatMap { textViews[$0]?.frame }
    }

    // MARK: Straight-line preview (drawn by the canvas while a held stroke is being straightened)

    func showPreview(from start: CGPoint, to end: CGPoint, width: CGFloat, color: UIColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: start.x * zoom, y: start.y * zoom))
        path.addLine(to: CGPoint(x: end.x * zoom, y: end.y * zoom))
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

    /// The eraser passing over a tape or a text box removes it.
    func erase(at point: CGPoint) {
        let tapes = items.tapes.filter { !Self.hit($0, point, slack: 4) }
        let texts = items.texts.filter { text in
            guard let view = textViews[text.id] else { return true }
            return !view.frame.contains(CGPoint(x: point.x * zoom, y: point.y * zoom))
        }
        guard tapes.count != items.tapes.count || texts.count != items.texts.count else { return }
        items.tapes = tapes
        items.texts = texts
        layoutItems()
        onChange(items)
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

    // MARK: Gestures

    private func pagePoint(_ recognizer: UIGestureRecognizer) -> CGPoint {
        let point = recognizer.location(in: self)
        return CGPoint(x: point.x / zoom, y: point.y / zoom)
    }

    private func text(at point: CGPoint) -> NoteText? {
        items.texts.last { text in
            textViews[text.id]?.frame.contains(CGPoint(x: point.x * zoom, y: point.y * zoom)) ?? false
        }
    }

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
            onChange(items)
        case .text:
            if editing != nil {
                endEditing()
            } else if let text = text(at: point) {
                beginEditing(text.id)
            } else {
                let x = Double(min(max(point.x, 8), pageSize.width - 88))
                let width = max(80, min(240, Double(pageSize.width) - x - 8))
                let y = max(4, Double(point.y) - textStyle.size * 0.8)
                let text = NoteText(
                    id: NotesData.newID("text"), x: x, y: y, width: width, text: "",
                    size: textStyle.size, color: textStyle.color, bold: textStyle.bold, background: textStyle.background
                )
                items.texts.append(text)
                layoutItems()
                beginEditing(text.id)
            }
        }
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        let point = pagePoint(recognizer)
        switch recognizer.state {
        case .began:
            drag = nil
            if mode == .tape {
                let id = NotesData.newID("tape")
                items.tapes.append(NoteTape(
                    id: id, x1: Double(point.x), y1: Double(point.y), x2: Double(point.x), y2: Double(point.y),
                    width: tapeWidth, color: tapeColor, revealed: false
                ))
                drag = .tape(id)
            } else if mode == .text {
                let touch = recognizer.location(in: self)
                if let editing, !handle.isHidden, hypot(touch.x - handle.center.x, touch.y - handle.center.y) < 24 {
                    drag = .resize(editing)
                } else if let text = text(at: point) {
                    drag = .move(text.id, CGPoint(x: point.x - CGFloat(text.x), y: point.y - CGFloat(text.y)))
                }
            }
        case .changed:
            switch drag {
            case .tape(let id):
                guard let index = items.tapes.firstIndex(where: { $0.id == id }) else { return }
                items.tapes[index].x2 = Double(point.x)
                items.tapes[index].y2 = Double(point.y)
            case .move(let id, let offset):
                guard let index = items.texts.firstIndex(where: { $0.id == id }) else { return }
                items.texts[index].x = Double(min(max(point.x - offset.x, 0), pageSize.width - 20))
                items.texts[index].y = Double(min(max(point.y - offset.y, 0), pageSize.height - 20))
            case .resize(let id):
                guard let index = items.texts.firstIndex(where: { $0.id == id }) else { return }
                // The handle sits a little right of the box's edge.
                items.texts[index].width = max(60, Double(point.x - 14 / zoom) - items.texts[index].x)
            case nil:
                return
            }
            layoutItems()
        case .ended, .cancelled, .failed:
            guard let finished = drag else { return }
            drag = nil
            if case .tape(let id) = finished, let index = items.tapes.firstIndex(where: { $0.id == id }) {
                let tape = items.tapes[index]
                // A touch that barely moved isn't a tape.
                if hypot(tape.x2 - tape.x1, tape.y2 - tape.y1) < 8 { items.tapes.remove(at: index) }
            }
            layoutItems()
            onChange(items)
        default:
            break
        }
    }

    // MARK: Text editing

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
        onChange(items)
    }

    /// The options changed while a box is being edited: it takes them on.
    private func restyleEditing() {
        guard let id = editing, let index = items.texts.firstIndex(where: { $0.id == id }) else { return }
        items.texts[index].size = textStyle.size
        items.texts[index].color = textStyle.color
        items.texts[index].bold = textStyle.bold
        items.texts[index].background = textStyle.background
        layoutItems()
    }

    func textViewDidChange(_ textView: UITextView) {
        guard let id = editing, let index = items.texts.firstIndex(where: { $0.id == id }) else { return }
        items.texts[index].text = textView.text
        layoutItems()
        onEditingFrame(textView.frame)
    }
}

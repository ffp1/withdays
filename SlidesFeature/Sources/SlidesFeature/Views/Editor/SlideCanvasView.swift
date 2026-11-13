import SwiftUI

/// The slide being edited, fitted to the space with margins. A tap selects an element and a tap on the selected
/// text box (or table cell) starts typing; a drag that starts on an element moves it; a sideways swipe that starts
/// on empty slide or outside the slide goes to the next / previous slide.
struct SlideCanvasView: View {
    @Bindable var editor: DeckEditor
    let textController: TextEditingController
    let showsGuides: Bool
    /// Text just inserted is selected whole, so typing replaces it.
    @Binding var selectAllOnEdit: Bool

    @State private var dragOrigin: SlideElement?
    @State private var pinchOrigin: SlideElement?
    /// +1 when the last switch went forward, for the slide's direction.
    @State private var forward = true

    var body: some View {
        GeometryReader { geo in
            let scale = min((geo.size.width - 32) / 1920, (geo.size.height - 32) / 1080)
            let size = CGSize(width: 1920 * scale, height: 1080 * scale)
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { deselect() }
                    .gesture(swipe)
                slide(scale: scale, size: size)
                    .frame(width: size.width, height: size.height)
                    .id(editor.current.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .onChange(of: editor.currentIndex) { old, new in forward = new >= old }
    }

    // MARK: Slide

    private func slide(scale: CGFloat, size: CGSize) -> some View {
        let slide = editor.current
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                SlideBackgroundView(background: slide.background, deck: editor.deckID)
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { deselect() }
                    .gesture(swipe)
                ForEach(slide.elements) { element in
                    elementView(element, scale: scale)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

            if showsGuides {
                GuidesOverlay()
                    .frame(width: size.width, height: size.height)
            }
            if let element = editor.selectedElement {
                SelectionOverlay(editor: editor, element: element, scale: scale, editing: editor.editing != nil)
            }
            if let editing = editor.editing, let element = editor.selectedElement, let text = editor.editingText() {
                textEditor(editing, element: element, text: text, scale: scale)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(.named("slide"))
        .simultaneousGesture(pinch(scale: scale))
    }

    private func elementView(_ element: SlideElement, scale: CGFloat) -> some View {
        let frame = element.frame.cg
        let padding = SlideRenderer.padding
        return ElementRenderView(element: displayed(element), deck: editor.deckID, scale: scale)
            .frame(width: (frame.width + padding * 2) * scale, height: (frame.height + padding * 2) * scale)
            // The padding (room for strokes and shadows) only counts a little for touches.
            .contentShape(Rectangle().inset(by: max(padding * scale - 10, 0)))
            .rotationEffect(.degrees(element.rotation))
            .opacity(element.opacity)
            .position(x: frame.midX * scale, y: frame.midY * scale)
            .onTapGesture(coordinateSpace: .named("slide")) { location in
                tap(element, at: CGPoint(x: location.x / scale, y: location.y / scale))
            }
            .gesture(move(element, scale: scale))
            .accessibilityElement()
            .accessibilityLabel(element.kindLabel)
            .accessibilityAddTraits(editor.selection == element.id ? [.isButton, .isSelected] : .isButton)
    }

    /// What's being typed in isn't drawn underneath the text view.
    private func displayed(_ element: SlideElement) -> SlideElement {
        guard let editing = editor.editing, editing.elementID == element.id else { return element }
        var shown = element
        switch (editing, element.content) {
        case (.text, .text):
            shown.content = .text(TextBoxElement(text: RichText(runs: [])))
        case (.cell(_, let row, let column), .table(var table)):
            if table.cells.indices.contains(row), table.cells[row].indices.contains(column) {
                table.cells[row][column].text.runs = []
            }
            shown.content = .table(table)
        default:
            break
        }
        return shown
    }

    // MARK: Typing

    @ViewBuilder
    private func textEditor(_ editing: EditTarget, element: SlideElement, text: RichText, scale: CGFloat) -> some View {
        let frame = element.frame.cg
        let area: CGRect = {
            if case .cell(_, let row, let column) = editing, case .table(let table) = element.content {
                return table.cellRect(row: row, column: column, in: frame.size)
            }
            return CGRect(origin: .zero, size: frame.size)
        }()
        // The area's middle, turned with the element around the element's middle.
        let angle = element.rotation * .pi / 180
        let local = CGPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2)
        let center = CGPoint(
            x: frame.midX + local.x * CGFloat(cos(angle)) - local.y * CGFloat(sin(angle)),
            y: frame.midY + local.x * CGFloat(sin(angle)) + local.y * CGFloat(cos(angle))
        )
        let inset: CGFloat = if case .cell = editing { SlideRenderer.cellInset } else { 0 }
        RichTextEditingView(
            text: text, size: area.size, inset: inset, scale: scale, controller: textController,
            selectAll: selectAllOnEdit
        ) { changed in
            editor.setEditingText(changed)
        }
        .id(editingKey(editing))
        .frame(width: area.width * scale, height: area.height * scale)
        .rotationEffect(.degrees(element.rotation))
        .opacity(element.opacity)
        .position(x: center.x * scale, y: center.y * scale)
        .onAppear { selectAllOnEdit = false }
    }

    private func editingKey(_ target: EditTarget) -> String {
        switch target {
        case .text(let id): "text-\(id)"
        case .cell(let id, let row, let column): "cell-\(id)-\(row)-\(column)"
        }
    }

    // MARK: Gestures

    /// `point` is in slide points.
    private func tap(_ element: SlideElement, at point: CGPoint) {
        guard editor.selection == element.id else {
            finishTyping()
            editor.selection = element.id
            return
        }
        switch element.content {
        case .text:
            editor.editing = .text(element.id)
        case .table(let table):
            // The cell under the finger, in the table's own (unturned) axes.
            let frame = element.frame.cg
            let angle = -element.rotation * .pi / 180
            let dx = Double(point.x - frame.midX)
            let dy = Double(point.y - frame.midY)
            let local = CGPoint(
                x: CGFloat(dx * cos(angle) - dy * sin(angle)) + frame.width / 2,
                y: CGFloat(dx * sin(angle) + dy * cos(angle)) + frame.height / 2
            )
            for row in 0..<table.rows {
                for column in 0..<table.columns where table.cellRect(row: row, column: column, in: frame.size).contains(local) {
                    if editor.editing != nil { textController.finish() }
                    editor.editing = .cell(element.id, row: row, column: column)
                    return
                }
            }
        default:
            break
        }
    }

    private func move(_ element: SlideElement, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("slide"))
            .onChanged { value in
                if dragOrigin?.id != element.id {
                    finishTyping()
                    editor.selection = element.id
                    editor.beginInteraction()
                    dragOrigin = element
                }
                guard var moved = dragOrigin else { return }
                moved.move(by: Double(value.translation.width / scale), Double(value.translation.height / scale))
                editor.changeElement(element.id) { $0 = moved }
            }
            .onEnded { _ in
                dragOrigin = nil
                editor.endInteraction()
            }
    }

    /// Pinching resizes the selected element around its middle.
    private func pinch(scale: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard editor.editing == nil, let selected = editor.selectedElement else { return }
                if pinchOrigin?.id != selected.id {
                    editor.beginInteraction()
                    pinchOrigin = selected
                }
                guard let origin = pinchOrigin else { return }
                let factor = max(0.1, min(Double(value.magnification), 10))
                editor.changeElement(origin.id) { $0 = Self.scaled(origin, by: factor) }
            }
            .onEnded { _ in
                pinchOrigin = nil
                editor.endInteraction()
            }
    }

    static func scaled(_ element: SlideElement, by factor: Double) -> SlideElement {
        var result = element
        let center = element.frame.center
        if case .line(var line) = element.content {
            for point in [\LineElement.start, \LineElement.end] {
                let value = line[keyPath: point]
                line[keyPath: point] = SlidePoint(
                    x: Double(center.x) + (value.x - Double(center.x)) * factor,
                    y: Double(center.y) + (value.y - Double(center.y)) * factor
                )
            }
            result.content = .line(line)
            result.syncLineFrame()
            return result
        }
        let width = max(element.frame.width * factor, 16)
        let height = max(element.frame.height * factor, 16)
        result.frame = SlideRect(x: Double(center.x) - width / 2, y: Double(center.y) - height / 2, width: width, height: height)
        return result
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 60, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                let target = editor.currentIndex + (dx < 0 ? 1 : -1)
                guard editor.slides.indices.contains(target) else { return }
                finishTyping()
                withAnimation(.snappy(duration: 0.3)) { editor.currentIndex = target }
            }
    }

    private func deselect() {
        finishTyping()
        editor.selection = nil
    }

    private func finishTyping() {
        guard editor.editing != nil else { return }
        textController.finish()
        editor.editing = nil
    }
}

/// The selected element's frame: eight handles to resize, one above to turn it. A line has a handle on each end.
struct SelectionOverlay: View {
    @Bindable var editor: DeckEditor
    let element: SlideElement
    let scale: CGFloat
    let editing: Bool

    @State private var origin: SlideElement?

    private static let handles: [(x: CGFloat, y: CGFloat)] = [
        (0, 0), (0.5, 0), (1, 0), (1, 0.5), (1, 1), (0.5, 1), (0, 1), (0, 0.5),
    ]

    var body: some View {
        if case .line(let line) = element.content {
            lineHandles(line)
        } else {
            frameHandles
        }
    }

    private var frameHandles: some View {
        let frame = element.frame.cg
        let width = frame.width * scale
        let height = frame.height * scale
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(SlidesTheme.brand, lineWidth: 1.5)
                .frame(width: width, height: height)
                .allowsHitTesting(false)
            if !editing {
                // The turning handle, on a short stem above the top edge.
                Rectangle()
                    .fill(SlidesTheme.brand)
                    .frame(width: 1.5, height: 22)
                    .position(x: width / 2, y: -11)
                    .allowsHitTesting(false)
                handle
                    .position(x: width / 2, y: -28)
                    .gesture(rotate)
                    .accessibilityLabel("回転")
                ForEach(Self.handles.indices, id: \.self) { index in
                    let point = Self.handles[index]
                    handle
                        .position(x: point.x * width, y: point.y * height)
                        .gesture(resize(point))
                        .accessibilityLabel("サイズ変更")
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .rotationEffect(.degrees(element.rotation))
        .position(x: frame.midX * scale, y: frame.midY * scale)
    }

    private var handle: some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(SlidesTheme.brand, lineWidth: 2))
            .frame(width: 14, height: 14)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private func lineHandles(_ line: LineElement) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            handle
                .position(x: line.start.x * scale, y: line.start.y * scale)
                .gesture(moveEnd(\.start))
                .accessibilityLabel("始点")
            handle
                .position(x: line.end.x * scale, y: line.end.y * scale)
                .gesture(moveEnd(\.end))
                .accessibilityLabel("終点")
        }
    }

    private func moveEnd(_ end: WritableKeyPath<LineElement, SlidePoint>) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("slide"))
            .onChanged { value in
                if origin == nil {
                    origin = element
                    editor.beginInteraction()
                }
                guard let origin, case .line(var line) = origin.content else { return }
                let point = line[keyPath: end]
                line[keyPath: end] = SlidePoint(
                    x: point.x + Double(value.translation.width / scale),
                    y: point.y + Double(value.translation.height / scale)
                )
                editor.changeElement(origin.id) { element in
                    element.content = .line(line)
                    element.syncLineFrame()
                }
            }
            .onEnded { _ in
                origin = nil
                editor.endInteraction()
            }
    }

    /// Drags one edge or corner; the opposite one stays put, also when the element is turned.
    private func resize(_ handle: (x: CGFloat, y: CGFloat)) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("slide"))
            .onChanged { value in
                if origin == nil {
                    origin = element
                    editor.beginInteraction()
                }
                guard let origin else { return }
                let angle = origin.rotation * .pi / 180
                // The drag in the element's own (unturned) axes, in slide points.
                let dx = Double(value.translation.width / scale)
                let dy = Double(value.translation.height / scale)
                let localX = dx * cos(angle) + dy * sin(angle)
                let localY = -dx * sin(angle) + dy * cos(angle)
                let width = origin.frame.width
                let height = origin.frame.height
                var left = -width / 2, right = width / 2, top = -height / 2, bottom = height / 2
                if handle.x == 0 { left = min(left + localX, right - 16) }
                if handle.x == 1 { right = max(right + localX, left + 16) }
                if handle.y == 0 { top = min(top + localY, bottom - 16) }
                if handle.y == 1 { bottom = max(bottom + localY, top + 16) }
                let shiftX = (left + right) / 2
                let shiftY = (top + bottom) / 2
                let center = origin.frame.center
                let newCenterX = Double(center.x) + shiftX * cos(angle) - shiftY * sin(angle)
                let newCenterY = Double(center.y) + shiftX * sin(angle) + shiftY * cos(angle)
                let newWidth = right - left
                let newHeight = bottom - top
                editor.changeElement(origin.id) { element in
                    element.frame = SlideRect(x: newCenterX - newWidth / 2, y: newCenterY - newHeight / 2, width: newWidth, height: newHeight)
                }
            }
            .onEnded { _ in
                origin = nil
                editor.endInteraction()
            }
    }

    /// Turns the element toward the finger; it settles on every 45° when close.
    private var rotate: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("slide"))
            .onChanged { value in
                if origin == nil {
                    origin = element
                    editor.beginInteraction()
                }
                guard let origin else { return }
                let center = origin.frame.center
                let dx = Double(value.location.x / scale) - Double(center.x)
                let dy = Double(value.location.y / scale) - Double(center.y)
                var degrees = atan2(dy, dx) * 180 / .pi + 90
                degrees = degrees.truncatingRemainder(dividingBy: 360)
                if degrees < 0 { degrees += 360 }
                let nearest = (degrees / 45).rounded() * 45
                if abs(degrees - nearest) < 4 { degrees = nearest.truncatingRemainder(dividingBy: 360) }
                editor.changeElement(origin.id) { $0.rotation = degrees }
            }
            .onEnded { _ in
                origin = nil
                editor.endInteraction()
            }
    }
}

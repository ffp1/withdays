import SwiftUI
import UIKit

/// The text view being typed in, for the accessory bar and the format sheet: formatting goes to the
/// selected range, or to what's typed next when nothing is selected. The text view shows the text at the size
/// it's drawn on screen (`scale` × slide points); runs remember their slide sizes, so reading back is exact.
@MainActor
@Observable
final class TextEditingController {
    @ObservationIgnored weak var textView: UITextView?
    /// The text's box settings and fallback formatting.
    @ObservationIgnored var base = RichText(runs: [])
    @ObservationIgnored var scale: CGFloat = 1
    @ObservationIgnored var onChange: ((RichText) -> Void)?
    /// Bumped when the selection or the text changes, so the bar and the sheet show what's there.
    private(set) var revision = 0

    var isActive: Bool { textView != nil }

    func touch() {
        revision += 1
    }

    /// What's typed next in an empty box (or after the formatting was reset).
    var baseAttributes: [NSAttributedString.Key: Any] {
        RichTextConverter.attributes(base.baseRun, in: base, scale: scale)
    }

    /// The formatting at the start of the selection (or what's typed next).
    func currentRun() -> TextRun {
        _ = revision
        guard let textView else { return base.baseRun }
        let range = textView.selectedRange
        let attributes: [NSAttributedString.Key: Any]
        if range.length > 0, range.location < textView.textStorage.length {
            attributes = textView.textStorage.attributes(at: range.location, effectiveRange: nil)
        } else {
            attributes = textView.typingAttributes
        }
        return RichTextConverter.run(from: attributes, scale: scale, fallback: base.baseRun)
    }

    func applyRun(_ change: (inout TextRun) -> Void) {
        guard let textView else { return }
        let range = textView.selectedRange
        if range.length == 0 {
            var run = RichTextConverter.run(from: textView.typingAttributes, scale: scale, fallback: base.baseRun)
            change(&run)
            textView.typingAttributes = RichTextConverter.attributes(run, in: base, scale: scale)
            touch()
            return
        }
        let storage = textView.textStorage
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { attributes, part, _ in
            var run = RichTextConverter.run(from: attributes, scale: scale, fallback: base.baseRun)
            change(&run)
            storage.setAttributes(RichTextConverter.attributes(run, in: base, scale: scale), range: part)
        }
        storage.endEditing()
        textView.selectedRange = range
        sync()
    }

    /// Alignment, spacing and effects belong to the whole box.
    func applyBox(_ change: (inout RichText) -> Void) {
        guard let textView else { return }
        var text = RichTextConverter.richText(from: textView.attributedText, base: base, scale: scale)
        change(&text)
        base.hAlign = text.hAlign
        base.vAlign = text.vAlign
        base.lineSpacing = text.lineSpacing
        base.charSpacing = text.charSpacing
        base.outline = text.outline
        base.shadow = text.shadow
        let range = textView.selectedRange
        textView.attributedText = RichTextConverter.attributed(text, scale: scale)
        textView.selectedRange = range
        var typing = RichTextConverter.run(from: textView.typingAttributes, scale: scale, fallback: base.baseRun)
        typing.text = ""
        textView.typingAttributes = RichTextConverter.attributes(typing, in: base, scale: scale)
        sync()
    }

    /// The view was zoomed while typing: the same text at the new size, the caret where it was.
    func rescale(_ newScale: CGFloat) {
        guard let textView, abs(newScale - scale) > 0.0001 else { return }
        let text = RichTextConverter.richText(from: textView.attributedText, base: base, scale: scale)
        scale = newScale
        let range = textView.selectedRange
        textView.attributedText = RichTextConverter.attributed(text, scale: newScale)
        textView.selectedRange = range
        textView.typingAttributes = baseAttributes
    }

    func sync() {
        guard let textView else { return }
        let text = RichTextConverter.richText(from: textView.attributedText, base: base, scale: scale)
        onChange?(text)
        if let container = textView.superview as? RichTextContainerView {
            container.text = base
            container.alignVertically()
        }
        touch()
    }

    func finish() {
        textView?.resignFirstResponder()
        textView = nil
        onChange = nil
        touch()
    }
}

/// Typing in a text box or a table cell on the canvas, at the size the slide is shown, so the text wraps and
/// aligns where it will be drawn. Japanese input is left alone: the text is only read back, never rewritten.
struct RichTextEditingView: UIViewRepresentable {
    let text: RichText
    /// The box, in slide points.
    let size: CGSize
    /// In slide points.
    let inset: CGFloat
    let scale: CGFloat
    let controller: TextEditingController
    var selectAll = false
    var onChange: (RichText) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> RichTextContainerView {
        let container = RichTextContainerView()
        let textView = container.textView
        textView.delegate = context.coordinator
        controller.textView = textView
        controller.base = text
        controller.scale = scale
        controller.onChange = onChange
        // The box's own font and alignment from the start, so the first letters typed into an empty box
        // look as they will (UIKit falls back to these when it resets what's typed next).
        let base = controller.baseAttributes
        textView.font = base[.font] as? UIFont
        textView.textColor = text.baseRun.color.uiColor
        textView.textAlignment = (base[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .left
        textView.attributedText = RichTextConverter.attributed(text, scale: scale)
        textView.typingAttributes = base
        textView.tintColor = SlidesTheme.brandUI
        container.text = text
        container.inset = inset * scale
        let selectAll = selectAll
        DispatchQueue.main.async {
            textView.becomeFirstResponder()
            if selectAll {
                textView.selectedRange = NSRange(location: 0, length: textView.textStorage.length)
            } else {
                textView.selectedRange = NSRange(location: textView.textStorage.length, length: 0)
            }
            if textView.textStorage.length == 0 { textView.typingAttributes = controller.baseAttributes }
            controller.touch()
        }
        return container
    }

    func updateUIView(_ container: RichTextContainerView, context: Context) {
        controller.onChange = onChange
        controller.rescale(scale)
        if container.inset != inset * scale {
            container.inset = inset * scale
            container.setNeedsLayout()
        }
    }

    static func dismantleUIView(_ container: RichTextContainerView, coordinator: Coordinator) {
        container.textView.resignFirstResponder()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let controller: TextEditingController

        init(controller: TextEditingController) {
            self.controller = controller
        }

        func textViewDidChange(_ textView: UITextView) {
            MainActor.assumeIsolated { controller.sync() }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            MainActor.assumeIsolated {
                // In an empty box UIKit forgets the formatting when the caret moves; give it back.
                if textView.textStorage.length == 0 {
                    textView.typingAttributes = controller.baseAttributes
                }
                controller.touch()
            }
        }
    }
}

/// Holds the text view at the box's on-screen size and keeps its text placed by the box's vertical alignment.
final class RichTextContainerView: UIView {
    let textView = UITextView()
    var text = RichText(runs: [])
    /// On-screen points.
    var inset: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        textView.backgroundColor = .clear
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.isScrollEnabled = false
        textView.clipsToBounds = false
        textView.autocorrectionType = .default
        // Slide content keeps its colors in dark mode.
        textView.overrideUserInterfaceStyle = .light
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
        alignVertically()
    }

    /// Top / middle / bottom, as the slide draws it.
    func alignVertically() {
        let width = max(bounds.width - inset * 2, 1)
        let height = RichTextConverter.height(of: textView.attributedText, width: width)
        let space = max(bounds.height - inset * 2 - height, 0)
        let top: CGFloat = switch text.vAlign {
        case .top: 0
        case .middle: space / 2
        case .bottom: space
        }
        textView.textContainerInset = UIEdgeInsets(top: inset + top, left: inset, bottom: inset, right: inset)
    }
}

/// Above the keyboard while typing: Aa (the format sheet), bold, italic, underline, size, and 完了.
struct TextAccessoryBar: View {
    let controller: TextEditingController
    var openFormat: () -> Void
    var done: () -> Void

    var body: some View {
        let run = controller.currentRun()
        HStack(spacing: 4) {
            barButton("textformat", label: "書式", active: false, action: openFormat)
            barButton("bold", label: "太字", active: run.bold) { controller.applyRun { $0.bold.toggle() } }
            barButton("italic", label: "斜体", active: run.italic) { controller.applyRun { $0.italic.toggle() } }
            barButton("underline", label: "下線", active: run.underline) { controller.applyRun { $0.underline.toggle() } }
            Spacer(minLength: 2)
            barButton("minus", label: "小さく", active: false) {
                controller.applyRun { $0.size = max(8, $0.size - 2) }
            }
            Text("\(Int(run.size.rounded()))")
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .frame(minWidth: 30)
            barButton("plus", label: "大きく", active: false) {
                controller.applyRun { $0.size = min(400, $0.size + 2) }
            }
            Spacer(minLength: 2)
            Button("完了", action: done)
                .font(.system(size: 15, weight: .bold))
                .brandGlass()
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func barButton(_ icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(active ? SlidesTheme.onBrand : Color.primary)
                .frame(width: 40, height: 40)
                .background {
                    if active { Circle().fill(SlidesTheme.brand) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

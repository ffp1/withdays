import SwiftUI
import UIKit

/// The text view being typed in, for the accessory bar and the format sheet: formatting goes to the
/// selected range, or to what's typed next when nothing is selected.
@MainActor
@Observable
final class TextEditingController {
    @ObservationIgnored weak var textView: UITextView?
    /// The text's box settings and fallback formatting.
    @ObservationIgnored var base = RichText(runs: [])
    @ObservationIgnored var onChange: ((RichText) -> Void)?
    /// Bumped when the selection or the text changes, so the bar and the sheet show what's there.
    private(set) var revision = 0

    var isActive: Bool { textView != nil }

    func touch() {
        revision += 1
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
        return RichTextConverter.run(from: attributes, scale: 1, fallback: base.baseRun)
    }

    func applyRun(_ change: (inout TextRun) -> Void) {
        guard let textView else { return }
        let range = textView.selectedRange
        if range.length == 0 {
            var run = RichTextConverter.run(from: textView.typingAttributes, scale: 1, fallback: base.baseRun)
            change(&run)
            textView.typingAttributes = RichTextConverter.attributes(run, in: base, scale: 1)
            touch()
            return
        }
        let storage = textView.textStorage
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { attributes, part, _ in
            var run = RichTextConverter.run(from: attributes, scale: 1, fallback: base.baseRun)
            change(&run)
            storage.setAttributes(RichTextConverter.attributes(run, in: base, scale: 1), range: part)
        }
        storage.endEditing()
        textView.selectedRange = range
        sync()
    }

    /// Alignment and spacing belong to the whole box.
    func applyBox(_ change: (inout RichText) -> Void) {
        guard let textView else { return }
        var text = RichTextConverter.richText(from: textView.attributedText, base: base, scale: 1)
        change(&text)
        base.hAlign = text.hAlign
        base.vAlign = text.vAlign
        base.lineSpacing = text.lineSpacing
        base.charSpacing = text.charSpacing
        base.outline = text.outline
        base.shadow = text.shadow
        let range = textView.selectedRange
        textView.attributedText = RichTextConverter.attributed(text)
        textView.selectedRange = range
        var typing = RichTextConverter.run(from: textView.typingAttributes, scale: 1, fallback: base.baseRun)
        typing.text = ""
        textView.typingAttributes = RichTextConverter.attributes(typing, in: base, scale: 1)
        sync()
    }

    func sync() {
        guard let textView else { return }
        let text = RichTextConverter.richText(from: textView.attributedText, base: base, scale: 1)
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

/// Typing in a text box or a table cell on the canvas. The text view works in slide points and is scaled down,
/// so what's typed looks like the slide. Japanese input is left alone: the text is only read back, never rewritten.
struct RichTextEditingView: UIViewRepresentable {
    let text: RichText
    /// The box, in slide points.
    let size: CGSize
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
        textView.attributedText = RichTextConverter.attributed(text)
        textView.typingAttributes = RichTextConverter.attributes(text.baseRun, in: text, scale: 1)
        textView.tintColor = SlidesTheme.brandUI
        container.text = text
        container.inset = inset
        container.slideSize = size
        container.scale = scale
        controller.textView = textView
        controller.base = text
        controller.onChange = onChange
        let selectAll = selectAll
        DispatchQueue.main.async {
            textView.becomeFirstResponder()
            if selectAll {
                textView.selectedRange = NSRange(location: 0, length: textView.textStorage.length)
            } else {
                textView.selectedRange = NSRange(location: textView.textStorage.length, length: 0)
            }
            controller.touch()
        }
        return container
    }

    func updateUIView(_ container: RichTextContainerView, context: Context) {
        controller.onChange = onChange
        if container.slideSize != size || container.scale != scale || container.inset != inset {
            container.slideSize = size
            container.scale = scale
            container.inset = inset
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
            MainActor.assumeIsolated { controller.touch() }
        }
    }
}

/// Holds the scaled text view and keeps its text placed by the box's vertical alignment.
final class RichTextContainerView: UIView {
    let textView = UITextView()
    var text = RichText(runs: [])
    var inset: CGFloat = 0
    var slideSize = CGSize(width: 100, height: 100)
    var scale: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        textView.backgroundColor = .clear
        textView.textContainer.lineFragmentPadding = 0
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
        textView.transform = .identity
        textView.frame = CGRect(origin: .zero, size: slideSize)
        textView.transform = CGAffineTransform(scaleX: scale, y: scale)
        textView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        alignVertically()
    }

    /// Top / middle / bottom, as the slide draws it.
    func alignVertically() {
        let width = slideSize.width - inset * 2
        let height = RichTextConverter.height(of: textView.attributedText, width: width)
        let space = max(slideSize.height - inset * 2 - height, 0)
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

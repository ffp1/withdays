import SwiftUI
import UIKit

/// The full-screen title input, for a new deck (作成) or renaming one (変更).
struct TitleInputView: View {
    enum Mode {
        case create, rename
    }

    let mode: Mode
    var onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(mode: Mode, initial: String = "", onSubmit: @escaping (String) -> Void) {
        self.mode = mode
        self.onSubmit = onSubmit
        _text = State(initialValue: initial)
    }

    /// Read only to enable the button; nothing is trimmed or changed while typing.
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        // Centered in what's left above the keyboard.
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 24)
            Text(mode == .create ? "タイトルを入力" : "タイトルを変更")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.secondary)
            IMETitleField(text: $text, onSubmit: submit)
            HStack {
                Spacer()
                Button(action: submit) {
                    Text(mode == .create ? "作成" : "変更")
                        .font(.system(size: 17, weight: .bold))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                }
                .brandGlass(enabled: !trimmed.isEmpty)
                .disabled(trimmed.isEmpty)
            }
            Spacer(minLength: 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    private func submit() {
        let title = trimmed
        guard !title.isEmpty else { return }
        onSubmit(title)
        dismiss()
    }
}

/// A large, borderless title field that wraps. A text view underneath, so Japanese input (未確定文字列)
/// is never touched by the app: the text is only written back when nothing is being converted.
struct IMETitleField: UIViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = FocusingTextView()
        view.delegate = context.coordinator
        view.font = .systemFont(ofSize: 40, weight: .black)
        view.textColor = .label
        view.tintColor = SlidesTheme.brandTextUI
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.returnKeyType = .done
        view.autocorrectionType = .no
        view.text = text
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityLabel = "タイトル"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        guard view.markedTextRange == nil, view.text != text else { return }
        view.text = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitted.height, 48))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: IMETitleField

        init(_ parent: IMETitleField) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            textView.invalidateIntrinsicContentSize()
        }

        /// Return (完了) submits instead of adding a line; while converting it only confirms the conversion.
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n", textView.markedTextRange == nil else { return true }
            parent.onSubmit()
            return false
        }
    }
}

/// Takes the keyboard as soon as it's on screen.
private final class FocusingTextView: UITextView {
    private var tookFocus = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !tookFocus else { return }
        tookFocus = true
        DispatchQueue.main.async { [weak self] in self?.becomeFirstResponder() }
    }
}

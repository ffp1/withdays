import Foundation

/// The layouts a new slide can start from. Their placeholders are ordinary text boxes with default text.
enum SlideLayout: CaseIterable, Identifiable {
    case titleSubtitle, titleOnly, titleBody, bodyOnly, caption, blank

    var id: Self { self }

    var label: String {
        switch self {
        case .titleSubtitle: "タイトル+サブタイトル"
        case .titleOnly: "タイトルのみ"
        case .titleBody: "タイトル+本文"
        case .bodyOnly: "本文のみ"
        case .caption: "説明のみ（左下に小さな文字）"
        case .blank: "白紙"
        }
    }

    var icon: String {
        switch self {
        case .titleSubtitle: "rectangle.center.inset.filled"
        case .titleOnly: "rectangle.inset.filled"
        case .titleBody: "rectangle.topthird.inset.filled"
        case .bodyOnly: "text.alignleft"
        case .caption: "rectangle.bottomthird.inset.filled"
        case .blank: "rectangle"
        }
    }

    func make() -> SlideContent {
        var slide = SlideContent()
        switch self {
        case .titleSubtitle:
            slide.elements = [
                Self.box(x: 160, y: 300, width: 1600, height: 240, .plain("タイトルを入力", size: 104, bold: true, hAlign: .center, vAlign: .bottom)),
                Self.box(x: 160, y: 580, width: 1600, height: 140, .plain("サブタイトルを入力", size: 52, color: .gray, hAlign: .center, vAlign: .top)),
            ]
        case .titleOnly:
            slide.elements = [
                Self.box(x: 160, y: 400, width: 1600, height: 280, .plain("タイトルを入力", size: 104, bold: true, hAlign: .center, vAlign: .middle)),
            ]
        case .titleBody:
            slide.elements = [
                Self.box(x: 120, y: 80, width: 1680, height: 180, .plain("タイトルを入力", size: 80, bold: true, vAlign: .middle)),
                Self.box(x: 120, y: 300, width: 1680, height: 680, .plain("本文を入力", size: 48)),
            ]
        case .bodyOnly:
            slide.elements = [
                Self.box(x: 120, y: 120, width: 1680, height: 840, .plain("本文を入力", size: 48)),
            ]
        case .caption:
            slide.elements = [
                Self.box(x: 80, y: 930, width: 1100, height: 90, .plain("説明を入力", size: 32, color: .gray, vAlign: .bottom)),
            ]
        case .blank:
            break
        }
        return slide
    }

    private static func box(x: Double, y: Double, width: Double, height: Double, _ text: RichText) -> SlideElement {
        SlideElement(frame: SlideRect(x: x, y: y, width: width, height: height), content: .text(TextBoxElement(text: text)))
    }
}

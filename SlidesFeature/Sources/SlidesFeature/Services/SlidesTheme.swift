import SwiftUI
import UIKit

/// The feature's colors. Brand fills carry dark text (white on #02B9B9 is too faint);
/// brand-colored text uses a darker teal on light backgrounds. All three are asset colors, easy to change.
enum SlidesTheme {
    static let brand = Color("SlidesBrand", bundle: .module)
    static let onBrand = Color("SlidesOnBrand", bundle: .module)
    static let brandText = Color("SlidesBrandText", bundle: .module)

    static var brandUI: UIColor {
        UIColor(named: "SlidesBrand", in: .module, compatibleWith: nil) ?? UIColor(red: 0.008, green: 0.725, blue: 0.725, alpha: 1)
    }

    static var brandTextUI: UIColor {
        UIColor(named: "SlidesBrandText", in: .module, compatibleWith: nil) ?? UIColor(red: 0, green: 0.478, blue: 0.478, alpha: 1)
    }

    /// The swatches offered for text, shapes and backgrounds.
    static let swatches: [RGBA] = [
        RGBA(hex: 0x000000), RGBA(hex: 0xFFFFFF), RGBA(hex: 0x02B9B9), RGBA(hex: 0xE5484D), RGBA(hex: 0xF5A524),
        RGBA(hex: 0xF7D046), RGBA(hex: 0x30A46C), RGBA(hex: 0x2563EB), RGBA(hex: 0x8E4EC6),
    ]

    static let gradientPresets: [LinearGradientFill] = [
        LinearGradientFill(stops: [stop(0x02B9B9, 0), stop(0x2563EB, 1)], angle: 135),
        LinearGradientFill(stops: [stop(0xF5A524, 0), stop(0xE5484D, 1)], angle: 135),
        LinearGradientFill(stops: [stop(0x8E4EC6, 0), stop(0xE5484D, 1)], angle: 90),
        LinearGradientFill(stops: [stop(0x30A46C, 0), stop(0x02B9B9, 1)], angle: 45),
        LinearGradientFill(stops: [stop(0x111827, 0), stop(0x374151, 1)], angle: 90),
        LinearGradientFill(stops: [stop(0xFFFFFF, 0), stop(0xE6F7F7, 1)], angle: 90),
    ]

    private static func stop(_ hex: Int, _ location: Double) -> GradientStop {
        GradientStop(color: RGBA(hex: hex), location: location)
    }
}

extension RGBA {
    var color: Color { Color(uiColor: uiColor) }

    init(_ color: Color) {
        self.init(UIColor(color))
    }
}

/// Brand-tinted glass for primary actions, with dark text on it.
struct BrandGlassButtonStyle: ViewModifier {
    var enabled = true

    func body(content: Content) -> some View {
        if enabled {
            content
                .buttonStyle(.glassProminent)
                .tint(SlidesTheme.brand)
                .foregroundStyle(SlidesTheme.onBrand)
        } else {
            content
                .buttonStyle(.glass)
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    func brandGlass(enabled: Bool = true) -> some View {
        modifier(BrandGlassButtonStyle(enabled: enabled))
    }
}

/// The system share sheet, for exported files.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file to hand to the share sheet.
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

enum SlidesFormat {
    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

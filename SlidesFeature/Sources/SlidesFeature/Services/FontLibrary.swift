import CoreText
import Foundation
import SwiftUI
import UIKit

/// Public entry for the host app: registers fonts imported in Slides, so text set in them draws right away.
public enum SlidesFonts {
    @MainActor
    public static func registerImportedFonts() {
        FontLibrary.shared.reload()
    }
}

/// Fonts the user imported (.ttf / .otf), kept in Application Support and registered for this process.
@MainActor
@Observable
final class FontLibrary {
    static let shared = FontLibrary()

    struct ImportedFont: Identifiable, Hashable {
        let file: String
        let postScriptName: String
        let displayName: String
        var id: String { file }
        var ext: String { (file as NSString).pathExtension.lowercased() }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private(set) var imported: [ImportedFont] = []
    private var registered: Set<String> = []

    /// The system families offered, with the name shown. Ones not on this iPhone are left out.
    static let systemFamilies: [(family: String, label: String)] = [
        ("Hiragino Sans", "ヒラギノ角ゴシック"),
        ("Hiragino Mincho ProN", "ヒラギノ明朝 ProN"),
        ("Hiragino Maru Gothic ProN", "ヒラギノ丸ゴ ProN"),
        ("Noto Sans JP", "Noto Sans JP"),
        (FontFaces.systemFamily, "SF Pro"),
        ("Georgia", "Georgia"),
        ("Menlo", "Menlo"),
    ].filter { $0.family == FontFaces.systemFamily || !UIFont.fontNames(forFamilyName: $0.family).isEmpty }

    /// The imported fonts by family, each family's faces lightest first.
    var importedFamilies: [(family: String, faces: [ImportedFont])] {
        let grouped = Dictionary(grouping: imported) { UIFont(name: $0.postScriptName, size: 12)?.familyName ?? $0.displayName }
        return grouped.keys.sorted().map { family in
            (family, grouped[family]!.sorted { FontFaces.weight(of: $0.postScriptName) < FontFaces.weight(of: $1.postScriptName) })
        }
    }

    /// What to call a font in the picker: its family, and its weight when the family has more than one.
    func label(for name: String) -> String {
        let family = FontFaces.family(of: name)
        let familyLabel = Self.systemFamilies.first { $0.family == family }?.label
            ?? imported.first { $0.postScriptName == name }?.displayName
            ?? family
        let faces = FontFaces.faces(of: family)
        guard faces.count > 1 else { return familyLabel }
        return "\(familyLabel) \(FontFaces.faceLabel(name))"
    }

    /// Registers every font file in the folder (again after a launch).
    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: SlidesFiles.fonts, includingPropertiesForKeys: nil)) ?? []
        var fonts: [ImportedFont] = []
        for url in files where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            guard let descriptor = Self.descriptor(url) else { continue }
            register(url)
            let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String ?? url.lastPathComponent
            let display = CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String ?? name
            fonts.append(ImportedFont(file: url.lastPathComponent, postScriptName: name, displayName: display))
        }
        imported = fonts.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Copies a font file in and registers it; a file that isn't a font is refused.
    func importFont(from url: URL) throws -> ImportedFont {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard ["ttf", "otf"].contains(url.pathExtension.lowercased()), Self.descriptor(url) != nil else {
            throw Failure(message: "フォントを読み込めませんでした。")
        }
        let target = SlidesFiles.fonts.appending(path: url.lastPathComponent)
        if FileManager.default.fileExists(atPath: target.path) {
            CTFontManagerUnregisterFontsForURL(target as CFURL, .process, nil)
            registered.remove(target.lastPathComponent)
            try? FileManager.default.removeItem(at: target)
        }
        do {
            try FileManager.default.copyItem(at: url, to: target)
        } catch {
            throw Failure(message: "フォントを読み込めませんでした。")
        }
        reload()
        guard let font = imported.first(where: { $0.file == target.lastPathComponent }) else {
            throw Failure(message: "フォントを読み込めませんでした。")
        }
        return font
    }

    /// Text set in it keeps the name and falls back to the system font; importing it again brings it back.
    func delete(_ font: ImportedFont) {
        let url = SlidesFiles.fonts.appending(path: font.file)
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        registered.remove(font.file)
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    private func register(_ url: URL) {
        guard !registered.contains(url.lastPathComponent) else { return }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        // "Already registered" is fine too.
        registered.insert(url.lastPathComponent)
    }

    private static func descriptor(_ url: URL) -> CTFontDescriptor? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return nil }
        return descriptors.first
    }
}

/// Fonts by family and weight. The system font's weights are written "System-<weight>".
enum FontFaces {
    static let systemFamily = "System"

    private static let systemWeights: [(name: String, label: String, weight: UIFont.Weight)] = [
        ("System-UltraLight", "UltraLight", .ultraLight), ("System-Thin", "Thin", .thin), ("System-Light", "Light", .light),
        ("System", "Regular", .regular), ("System-Medium", "Medium", .medium), ("System-Semibold", "Semibold", .semibold),
        ("System-Bold", "Bold", .bold), ("System-Heavy", "Heavy", .heavy), ("System-Black", "Black", .black),
    ]

    static func systemWeight(_ name: String) -> UIFont.Weight? {
        guard name != "System", name.hasPrefix("System-") else { return nil }
        return systemWeights.first { $0.name == name }?.weight
    }

    static func family(of name: String) -> String {
        if name == "System" || name.hasPrefix("System-") || name.isEmpty { return systemFamily }
        if let family = UIFont(name: name, size: 12)?.familyName { return family }
        return name
    }

    /// The family's faces (PostScript names), lightest first.
    static func faces(of family: String) -> [String] {
        if family == systemFamily { return systemWeights.map(\.name) }
        return UIFont.fontNames(forFamilyName: family).sorted { weight(of: $0) < weight(of: $1) }
    }

    static func weight(of name: String) -> CGFloat {
        if name == "System" { return UIFont.Weight.regular.rawValue }
        if let system = systemWeight(name) { return system.rawValue }
        guard let font = UIFont(name: name, size: 12),
              let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any],
              let weight = traits[.weight] as? CGFloat else { return 0 }
        // Italics after their upright.
        return weight + (font.fontDescriptor.symbolicTraits.contains(.traitItalic) ? 0.001 : 0)
    }

    /// "W3", "Bold", "Light Italic"…
    static func faceLabel(_ name: String) -> String {
        if name == "System" { return "Regular" }
        if let system = systemWeights.first(where: { $0.name == name }) { return system.label }
        if let face = UIFont(name: name, size: 12)?.fontDescriptor.object(forKey: .face) as? String { return face }
        return name
    }
}

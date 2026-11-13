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

    /// The system fonts offered: PostScript name and name shown. Ones not on this iPhone are left out.
    static let systemFonts: [(name: String, label: String)] = [
        ("HiraginoSans-W3", "ヒラギノ角ゴシック"),
        ("HiraMinProN-W3", "ヒラギノ明朝 ProN"),
        ("HiraMaruProN-W4", "ヒラギノ丸ゴ ProN"),
        ("NotoSansJP-Regular", "Noto Sans JP"),
        ("System", "SF Pro"),
        ("Georgia", "Georgia"),
        ("Menlo-Regular", "Menlo"),
    ].filter { $0.name == "System" || UIFont(name: $0.name, size: 12) != nil }

    /// What to call a font in the picker.
    func label(for name: String) -> String {
        if let system = Self.systemFonts.first(where: { $0.name == name }) { return system.label }
        if let font = imported.first(where: { $0.postScriptName == name }) { return font.displayName }
        return UIFont(name: name, size: 12)?.familyName ?? name
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

import Foundation
import ImageIO
import UIKit

/// Where the feature keeps its files: Application Support/Slides holds the store, each deck's images
/// (Assets/<deck id>/) and imported fonts; thumbnails go in Caches.
enum SlidesFiles {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appending(path: "Slides", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var storeURL: URL { root.appending(path: "Slides.store") }

    static let fonts: URL = {
        let url = root.appending(path: "Fonts", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let thumbnails: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appending(path: "SlidesThumbnails", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func assets(_ deck: UUID) -> URL {
        root.appending(path: "Assets", directoryHint: .isDirectory).appending(path: deck.uuidString, directoryHint: .isDirectory)
    }

    static func asset(_ name: String, deck: UUID) -> URL {
        assets(deck).appending(path: name)
    }

    /// Saves an image for the deck: JPEG and PNG as they are (full resolution), anything else as JPEG.
    /// Images are turned upright first, so the drawing code never deals with orientation.
    static func storeImage(_ data: Data, deck: UUID) throws -> (name: String, size: CGSize) {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw Failure(message: "画像を読み込めませんでした。")
        }
        let folder = assets(deck)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bytes = [UInt8](data.prefix(4))
        let isPNG = bytes.starts(with: [0x89, 0x50, 0x4E, 0x47])
        let isJPEG = bytes.starts(with: [0xFF, 0xD8])
        var output = data
        var ext = isPNG ? "png" : "jpg"
        if image.imageOrientation != .up || !(isPNG || isJPEG) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
            let upright = UIGraphicsImageRenderer(size: pixels, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: pixels))
            }
            if isPNG, let png = upright.pngData() {
                output = png
            } else if let jpeg = upright.jpegData(compressionQuality: 0.92) {
                output = jpeg
                ext = "jpg"
            }
        }
        let name = "\(UUID().uuidString).\(ext)"
        do {
            try output.write(to: folder.appending(path: name), options: .atomic)
        } catch {
            throw Failure(message: "画像を保存できませんでした。空き容量を確認してください。")
        }
        return (name, CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale))
    }

    /// Copies images from one deck's folder to another's (pasting slides, duplicating decks).
    static func copyAssets(_ names: some Sequence<String>, from source: UUID, to target: UUID) {
        guard source != target else { return }
        let folder = assets(target)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in Set(names) {
            let destination = folder.appending(path: name)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try? FileManager.default.copyItem(at: asset(name, deck: source), to: destination)
        }
    }

    static func deleteAssets(of deck: UUID) {
        try? FileManager.default.removeItem(at: assets(deck))
    }

    /// Bytes in a folder, recursively.
    static func folderSize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// A file name from a title, without characters file systems refuse.
    static func fileName(_ title: String, ext: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines).union(.controlCharacters)
        let cleaned = title.components(separatedBy: banned).joined(separator: "_").trimmingCharacters(in: .whitespaces)
        return "\(cleaned.isEmpty ? "スライド" : String(cleaned.prefix(80))).\(ext)"
    }

    /// A fresh folder in tmp for an export, so two exports never overwrite each other's file.
    static func exportFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SlidesExport", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Decoded images, shared by the canvas, thumbnails and exports.
enum SlideAssets {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 40
        return cache
    }()

    static func image(_ name: String, deck: UUID) -> UIImage? {
        let key = "\(deck.uuidString)/\(name)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(contentsOfFile: SlidesFiles.asset(name, deck: deck).path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Pixel size without decoding the whole image.
    static func pixelSize(_ name: String, deck: UUID) -> CGSize? {
        let url = SlidesFiles.asset(name, deck: deck) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double else { return nil }
        return CGSize(width: width, height: height)
    }
}

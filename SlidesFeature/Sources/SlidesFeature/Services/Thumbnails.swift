import CryptoKit
import SwiftUI
import UIKit

/// Slide thumbnails, rendered off the main thread and kept on disk by the slide's content,
/// so a changed slide gets a new one and an unchanged one is never drawn twice.
actor ThumbnailRenderer {
    static let shared = ThumbnailRenderer()

    private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    /// A key for the slide as it is now.
    nonisolated static func key(for data: Data, deck: UUID) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return "\(deck.uuidString.prefix(8))-\(hex)"
    }

    func image(for slide: SlideContent, deck: UUID, key: String, width: CGFloat) -> UIImage? {
        let name = "\(key)-\(Int(width)).png"
        if let cached = memory.object(forKey: name as NSString) { return cached }
        let url = SlidesFiles.thumbnails.appending(path: name)
        if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            memory.setObject(image, forKey: name as NSString)
            return image
        }
        let image = SlideRenderer.image(of: slide, deck: deck, width: width, scale: 2)
        memory.setObject(image, forKey: name as NSString)
        if let png = image.pngData() { try? png.write(to: url, options: .atomic) }
        return image
    }
}

/// A slide's thumbnail. It loads in the background; a changed slide is redrawn after a short pause.
struct SlideThumbnail: View {
    let slide: SlideContent?
    let data: Data?
    let deck: UUID
    let width: CGFloat
    var cornerRadius: CGFloat = 8

    @State private var image: UIImage?

    init(slide: SlideContent, deck: UUID, width: CGFloat, cornerRadius: CGFloat = 8) {
        self.slide = slide
        data = nil
        self.deck = deck
        self.width = width
        self.cornerRadius = cornerRadius
    }

    /// From a stored page: decoded only when its thumbnail isn't cached.
    init(data: Data, deck: UUID, width: CGFloat, cornerRadius: CGFloat = 8) {
        slide = nil
        self.data = data
        self.deck = deck
        self.width = width
        self.cornerRadius = cornerRadius
    }

    private var key: String {
        ThumbnailRenderer.key(for: data ?? slide?.encoded() ?? Data(), deck: deck)
    }

    var body: some View {
        Color.white
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .task(id: key) {
                let key = key
                // While the slide is being edited, wait for a pause before drawing it again.
                if image != nil { try? await Task.sleep(for: .milliseconds(350)) }
                guard !Task.isCancelled else { return }
                let content = slide ?? data.flatMap(SlideContent.decode)
                guard let content else { return }
                let rendered = await ThumbnailRenderer.shared.image(for: content, deck: deck, key: key, width: width * 2)
                guard !Task.isCancelled else { return }
                image = rendered
            }
            .accessibilityHidden(true)
    }
}

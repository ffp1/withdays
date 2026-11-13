import Foundation
import SwiftData
import UIKit
import Vision

/// Searching decks by title, the text in their slides, and the text recognized in their images.
enum SlidesSearch {
    /// Case, full-width / half-width and hiragana / katakana don't matter.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
        let katakana = folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded
        return katakana.lowercased()
    }

    /// Where a deck matched, for the caption under its card.
    enum Match: Equatable {
        case title
        case body(slide: Int)
        case image(slide: Int)

        var caption: String {
            switch self {
            case .title: "タイトルに一致"
            case .body(let slide): "スライド\(slide)の本文に一致"
            case .image(let slide): "スライド\(slide)の画像内テキストに一致"
            }
        }
    }

    /// The first place the deck matches: its title, then each slide's text, then each slide's images.
    static func match(_ deck: Deck, query: String, imageText: [String: String]) -> Match? {
        let needle = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return nil }
        if deck.searchTitle.contains(needle) { return .title }
        let pages = deck.sortedPages
        for (index, page) in pages.enumerated() where page.searchBody.contains(needle) {
            return .body(slide: index + 1)
        }
        for (index, page) in pages.enumerated() {
            for asset in page.assetNames {
                if imageText[ImageTextEntry.key(deck: deck.id, asset: asset)]?.contains(needle) == true {
                    return .image(slide: index + 1)
                }
            }
        }
        return nil
    }
}

/// Reads the text in images (Vision, on the device) in the background, one image at a time,
/// and keeps it in the search index. Run when images are added, and to fill in older ones.
@MainActor
final class ImageTextIndexer {
    static let shared = ImageTextIndexer()

    private var queue: [(key: String, url: URL)] = []
    private var running = false
    private weak var context: ModelContext?

    /// Every image in every deck that hasn't been read yet.
    func backfill(context: ModelContext) {
        self.context = context
        let known = Set(((try? context.fetch(FetchDescriptor<ImageTextEntry>())) ?? []).map(\.key))
        let decks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        for deck in decks {
            for page in deck.pages {
                for asset in page.assetNames {
                    let key = ImageTextEntry.key(deck: deck.id, asset: asset)
                    if !known.contains(key) { add(key, SlidesFiles.asset(asset, deck: deck.id)) }
                }
            }
        }
        runNext()
    }

    func index(_ asset: String, deck: UUID, context: ModelContext) {
        self.context = context
        add(ImageTextEntry.key(deck: deck, asset: asset), SlidesFiles.asset(asset, deck: deck))
        runNext()
    }

    private func add(_ key: String, _ url: URL) {
        guard !queue.contains(where: { $0.key == key }) else { return }
        queue.append((key, url))
    }

    private func runNext() {
        guard !running, !queue.isEmpty else { return }
        running = true
        let job = queue.removeFirst()
        Task.detached(priority: .utility) {
            let text = Self.recognize(job.url)
            await MainActor.run {
                self.store(job.key, text)
                self.running = false
                self.runNext()
            }
        }
    }

    private func store(_ key: String, _ text: String) {
        guard let context else { return }
        let existing = try? context.fetch(FetchDescriptor<ImageTextEntry>(predicate: #Predicate { $0.key == key }))
        if let entry = existing?.first {
            entry.text = SlidesSearch.normalize(text)
        } else {
            context.insert(ImageTextEntry(key: key, text: SlidesSearch.normalize(text)))
        }
        try? context.save()
    }

    /// Japanese and English; an image that can't be read gives "".
    nonisolated static func recognize(_ url: URL) -> String {
        guard let image = UIImage(contentsOfFile: url.path), let cgImage = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            return ""
        }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
}

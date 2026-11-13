import Foundation
import SwiftData

/// A presentation: its title, dates and slides. The slides' content is in `SlidePage` rows;
/// their images are files in the deck's asset folder.
@Model
final class Deck {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date
    var isFavorite: Bool
    var showsGuides: Bool
    /// The title, normalized for searching.
    var searchTitle: String
    @Relationship(deleteRule: .cascade, inverse: \SlidePage.deck) var pages: [SlidePage] = []

    init(title: String) {
        id = UUID()
        self.title = title
        createdAt = .now
        updatedAt = .now
        lastOpenedAt = .now
        isFavorite = false
        showsGuides = false
        searchTitle = SlidesSearch.normalize(title)
    }

    var sortedPages: [SlidePage] { pages.sorted { $0.order < $1.order } }

    var slides: [SlideContent] { sortedPages.compactMap { SlideContent.decode($0.data) } }

    func rename(_ title: String) {
        self.title = title
        searchTitle = SlidesSearch.normalize(title)
        updatedAt = .now
    }
}

/// One slide, stored as a JSON blob (its elements are value types; images are files, never inline).
@Model
final class SlidePage {
    @Attribute(.unique) var id: UUID
    var order: Int
    var data: Data
    /// The text in the slide's text boxes and tables, normalized for searching.
    var searchBody: String
    /// The image files the slide uses, for searching their recognized text.
    var assetNames: [String]
    var deck: Deck?

    init(_ slide: SlideContent, order: Int) {
        id = slide.id
        self.order = order
        data = slide.encoded()
        searchBody = SlidesSearch.normalize(slide.searchableText)
        assetNames = slide.assetNames
    }

    func update(_ slide: SlideContent, encoded: Data) {
        data = encoded
        searchBody = SlidesSearch.normalize(slide.searchableText)
        assetNames = slide.assetNames
    }
}

/// Text recognized in an image (OCR), by "<deck id>/<file>". Filled in the background; searched, never computed at query time.
@Model
final class ImageTextEntry {
    @Attribute(.unique) var key: String
    /// Normalized for searching.
    var text: String

    init(key: String, text: String) {
        self.key = key
        self.text = text
    }

    static func key(deck: UUID, asset: String) -> String {
        "\(deck.uuidString)/\(asset)"
    }
}

/// The feature's own SwiftData store, apart from the host app's data.
@MainActor
enum SlidesStore {
    static let container: ModelContainer = {
        let schema = Schema([Deck.self, SlidePage.self, ImageTextEntry.self])
        let configuration = ModelConfiguration("Slides", schema: schema, url: SlidesFiles.storeURL)
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }
        // A store that can't be opened shouldn't take the app down; work in memory and say so on save.
        let memory = ModelConfiguration("SlidesMemory", schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [memory])
    }()
}

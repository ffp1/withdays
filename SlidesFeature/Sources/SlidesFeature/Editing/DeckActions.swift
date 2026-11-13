import Foundation
import SwiftData

/// What can be done to a whole deck, from the home screen or the editor.
@MainActor
enum DeckActions {
    /// A new deck with one title slide.
    static func create(title: String, context: ModelContext) -> Deck {
        let deck = Deck(title: title)
        context.insert(deck)
        let page = SlidePage(SlideLayout.titleSubtitle.make(), order: 0)
        page.deck = deck
        context.insert(page)
        try? context.save()
        return deck
    }

    /// "<title>のコピー": new IDs, its own copy of the images, not a favorite, new dates.
    @discardableResult
    static func duplicate(_ deck: Deck, context: ModelContext) -> Deck {
        let copy = Deck(title: "\(deck.title)のコピー")
        copy.showsGuides = deck.showsGuides
        context.insert(copy)
        let slides = deck.slides
        for (index, slide) in slides.enumerated() {
            let page = SlidePage(slide.withNewIDs(), order: index)
            page.deck = copy
            context.insert(page)
        }
        SlidesFiles.copyAssets(slides.flatMap(\.assetNames), from: deck.id, to: copy.id)
        try? context.save()
        ImageTextIndexer.shared.backfill(context: context)
        return copy
    }

    /// For good: the deck, its pages, its images and their recognized text.
    static func delete(_ deck: Deck, context: ModelContext) {
        let prefix = deck.id.uuidString + "/"
        let entries = (try? context.fetch(FetchDescriptor<ImageTextEntry>())) ?? []
        for entry in entries where entry.key.hasPrefix(prefix) { context.delete(entry) }
        SlidesFiles.deleteAssets(of: deck.id)
        context.delete(deck)
        try? context.save()
    }

    static func toggleFavorite(_ deck: Deck, context: ModelContext) {
        deck.isFavorite.toggle()
        try? context.save()
    }

    static func rename(_ deck: Deck, to title: String, context: ModelContext) {
        deck.rename(title)
        try? context.save()
    }

    /// The deck's stored data plus its images on disk.
    static func fileSize(_ deck: Deck) -> Int64 {
        let data = deck.pages.reduce(Int64(0)) { $0 + Int64($1.data.count) }
        return data + SlidesFiles.folderSize(SlidesFiles.assets(deck.id))
    }
}

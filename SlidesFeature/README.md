# SlidesFeature

A presentation maker for iPhone (iOS 26+, SwiftUI + SwiftData), as a local Swift package.

## Embedding

```swift
import SlidesFeature

// Anywhere outside another NavigationStack: it owns its navigation and its own data store.
SlidesHomeView(onClose: { /* leave the feature */ })
```

Two things in the host app:

```swift
// 1. Register fonts imported in Slides at launch.
SlidesFonts.registerImportedFonts()

// 2. Let the player turn the screen (and list landscape in Info.plist's UISupportedInterfaceOrientations).
func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
    SlidesOrientation.supported
}
```

## Architecture

- **Model** (`Model/`): `Deck`, `SlidePage` and `ImageTextEntry` are SwiftData models. A slide's content is a `SlideContent` value (background, elements back to front, transition, animations) stored as JSON in its page. Images and imported fonts are files in Application Support; thumbnails are in Caches.
- **Rendering** (`Rendering/`): `SlideRenderer` draws slides with Core Graphics. The editor's element views, thumbnails and the PDF all use it, so a slide looks the same everywhere. `RichTextConverter` maps runs to attributed strings and back.
- **Editing** (`Editing/`): `DeckEditor` holds the open deck's slides as values, the selection, the undo history (`EditHistory`, snapshots, 100 steps, coalescing) and saving (debounced 0.5 s, and right away when leaving or going to the background).
- **Views** (`Views/`): home (grid, search, sort, card menus, title input, details), editor (canvas with selection handles and inline rich-text editing, page strip with drag reordering, contextual toolbar, format sheets), player (landscape, transitions, element animations).
- **Search** (`Services/SlidesSearch.swift`): titles and slide text are normalized when saved; text in images is read with Vision in the background and stored per image. Queries only compare stored strings.
- **Export** (`Export/`): PDF through `UIGraphicsPDFRenderer`; PPTX written as OOXML with a small built-in ZIP writer.

Decisions and their reasons are in `DECISIONS.md`.

## Tests

```sh
cd SlidesFeature
xcodebuild test -scheme SlidesFeature -destination 'platform=iOS Simulator,name=iPhone 17'
```

They cover the model (JSON, copies, tables, rich text), search normalization and matching, undo / redo, the PPTX package's parts and XML, and the PDF's pages.

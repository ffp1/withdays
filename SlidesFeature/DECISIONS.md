# DECISIONS

One line per decision: the decision, then why.

## Where it lives

- Slides is a local Swift package (`SlidesFeature`) inside the WithDays repository, opened from the ＋ hold menu in Cal: the requester asked for it inside WithDays, as its own package when that costs nothing.
- The package uses Swift 6 tools with the Swift 5 language mode: the same mode as WithDays (the requester asked to follow WithDays).
- Slides has its own SwiftData store (`Application Support/Slides/Slides.store`): it never touches WithDays' data and can be removed cleanly.
- `SlidesHomeView(onClose:)` adds a calendar button (top right) so the host can leave the feature; with no closure there's no button.
- WithDays' app delegate returns `SlidesOrientation.supported` and Info.plist lists landscape: the player needs landscape, everything else stays portrait.

## Data

- Each slide is one JSON blob in a `SlidePage` row (elements are Codable value types): a slide loads and saves in one read, and value types make undo snapshots cheap.
- Z-order is the order of `elements` (back to front) rather than a separate field: one source of truth, and reordering is an array move.
- Images are files in `Assets/<deck id>/`, named by UUID; JPEG and PNG are kept byte for byte, anything else (HEIC…) becomes JPEG; images are turned upright on import so drawing never deals with EXIF orientation.
- Imported fonts are files in `Application Support/Slides/Fonts`, registered for the process at launch and on import.
- Thumbnails are PNGs in Caches, keyed by a hash of the slide's JSON: an unchanged slide is never drawn twice and a changed one gets a new file.
- File size in 詳細 = the bytes of the deck's slide JSON + its asset folder.
- Line elements store their two ends; their frame is kept as the box around them.
- A deck's title slide keeps the placeholder text 「タイトルを入力」; the typed deck title is not copied into it (the spec doesn't say to).

## Look

- Brand colors are asset colors: SlidesBrand #02B9B9 (fills), SlidesOnBrand #00302F (text on brand fills), SlidesBrandText #007A7A light / #02B9B9 dark (brand-colored text) — §14-3.
- The title input is a sheet at the large detent (not a full-screen cover), so it can be swiped down: the spec has no close control — §14-5.
- The home search field and controls float over the grid (glass) and slide away while scrolling down; the smallest scroll up brings them back.
- Favorites filter is a segmented control (すべて / お気に入り) beside the sort button; no badge on cards — §14-11.
- Search results show "タイトルに一致" / "スライドNの本文に一致" / "スライドNの画像内テキストに一致" under each card — §14-4.

## Editor

- The editor's top controls are native toolbar items (back; undo / redo; ＋ / ▶ / ⋯ separated by `ToolbarSpacer`), so iOS 26 draws them as glass pills.
- A tap selects an element; tapping the selected text box (so also a double tap) starts typing; a selected table types in the tapped cell.
- A drag that starts on an element moves it; a sideways swipe that starts on empty slide or outside the slide changes slide — §14-8.
- With an element selected the glass bar shows its tools and その他 (複製, stacking order, 削除); with nothing selected it shows 背景 and トランジション — §9 / §14-9.
- 配置 for a text box is a menu of horizontal and vertical alignment; 色 is a short sheet with swatches and a picker.
- A new text box holds 「テキスト」, selected, so typing replaces it.
- Shapes insert at 520×360 (rect), 400×400 (circle, triangle, star), 520×300 (arrow); lines at 500 pt; tables 280×110 per cell up to 1600×860.
- Images: 写真 or ファイル is asked first (a dialog), then the picker; images are placed fitted inside 1280×720.
- Text formatting goes to the selected range while typing, to what's typed next when nothing is selected, and to the whole box when the box (not text) is selected.
- Table row heights and column widths are weights edited with sliders in 行/列 (with 均等にする); there's no dragging of borders.
- Table cell fills can go to all cells, the first row, or the cell being typed in.
- Guides are visual only, no snapping — §14-10. The turning handle settles on multiples of 45° within 4°.
- The ＋ in the strip and new slides from it go after the current slide — §14-6.
- Slide reordering uses system drag and drop (lift after a hold, brand insertion bar, the scroll view scrolls near its edges).
- Copy / paste of slides is in memory, in the app only; pasting into another deck copies the images over.

## Undo

- Snapshots of the slide array (copy-on-write) with a 100-step limit; drags, pinches and turns are one step from start to end; typing, sliders and color pickers on the same thing within 1 s merge into one step.
- Deck settings (guides, favorite, name) aren't part of undo.

## Player

- Tap in the middle third toggles the controls; right third → next (animation step first), left third → previous; controls hide after 3 s — §14-7.
- A swipe changes slide with every element in its final state; a tap runs the next step — §9.
- Animations before the first タップ時 run as the slide appears.
- Reduce Motion turns transitions into fades and drops movement from element animations.

## Export

- PDF: `UIGraphicsPDFRenderer`, one 1920×1080 pt page per slide, drawn by the same renderer as the screen (vector text and shapes, images at source resolution, fonts embedded by Core Graphics).
- PPTX: written by hand (no dependency). The ZIP is a small stored-entry writer (`ZipWriter`, CRC-32, no compression, no ZIP64): no third-party package is needed, so there's no license to track. Files are bigger than Office's compressed ones.
- PPTX units: 1 slide point = 6350 EMU (1920 pt across = 13.333 in); font size in PPTX = slide size ÷ 2.
- PPTX fonts go by family name; the system font is written as Helvetica Neue (Latin) / Hiragino Sans (East Asian).
- PPTX transitions map to fade / push / cover / zoom with fast / med / slow by duration; animations map to Appear (1), Fade (10), Fly In (2) and Zoom (53) presets.
- An element that can't be written as itself (an image whose file is gone) is written as a picture of it.

## Search

- OCR runs on images when they're added and fills in older ones in the background at launch; its text is stored per image ("<deck>/<file>") and only read at query time.
- Normalization: case, width (full / half) and hiragana / katakana folded; kanji readings aren't matched.
- Name sorting uses Japanese-locale comparison; kanji sort by code point (the system gives no readings).

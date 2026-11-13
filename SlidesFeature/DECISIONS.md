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
- Layout placeholders (「タイトルを入力」…) are empty text boxes with a placeholder shown in gray in the editor only; the player, thumbnails, PDF and PowerPoint leave them out. The typed deck title is not copied into the title slide.

## Look

- Brand colors are asset colors: SlidesBrand #02B9B9 (fills), SlidesOnBrand #00302F (text on brand fills), SlidesBrandText #007A7A light / #02B9B9 dark (brand-colored text) — §14-3.
- The title input is a sheet at the large detent (not a full-screen cover), so it can be swiped down: the spec has no close control — §14-5. Its content sits in the middle of what's above the keyboard; both labels are bold.
- The home search field and controls float over the grid (glass) and slide away while scrolling down; the smallest scroll up brings them back.
- Favorites filter is a segmented control (すべて / お気に入り) beside the sort button; favorites get a star at their thumbnail's top left (requested, replacing §14-11).
- The card's ⋯ is a plain button (no glass) beside the title, centered with it; holding the card shows the same menu.
- Search results show "タイトルに一致" / "スライドNの本文に一致" / "スライドNの画像内テキストに一致" under each card — §14-4.

## Editor

- The editor's top controls are drawn by the editor itself as glass pills (back; undo / redo; ＋ / ▶ / ⋯), not navigation-bar items: the bar's items sometimes went missing.
- ▶ plays from the first slide; holding it plays from the slide on screen.
- A tap selects an element; tapping the selected text box (so also a double tap) starts typing; a selected table types in the tapped cell.
- A drag that starts on an element moves it; a sideways swipe that starts on empty slide or outside the slide changes slide: right to left for the next one, left to right for the previous one — §14-8.
- Pinching with nothing selected zooms the view (up to 500 %) around the fingers: a scale while pinching, redrawn sharp when the fingers lift. Zoomed in, a drag on empty space moves it; the % button goes back to the whole slide. While two fingers are down, taps and drags on elements are ignored (a drag that becomes a pinch puts the element back).
- With an element selected the glass bar shows its tools and その他 (複製, stacking order, 削除); with nothing selected it shows 背景 and トランジション — §9 / §14-9.
- 配置 for a text box is a menu of horizontal and vertical alignment; 色 is a short sheet with swatches and a picker.
- A new text box holds 「テキスト」, selected, so typing replaces it.
- Shapes insert at 520×360 (rect), 400×400 (circle, triangle, star), 520×300 (arrow); lines at 500 pt; tables 280×110 per cell up to 1600×860.
- Images: 画像 opens a list (写真ライブラリ / ファイル), then the picker; images are placed fitted inside 1280×720.
- The editor draws images at up to 1600 px and only redraws an element when its look changes (not when it moves); exports use the full image.
- Text formatting goes to the selected range while typing, to what's typed next when nothing is selected, and to the whole box when the box (not text) is selected.
- Table row heights and column widths are weights edited with sliders in 行/列 (with 均等にする); there's no dragging of borders.
- Table cell fills can go to all cells, the first row, or the cell being typed in.
- Snapping (requested): moving, resizing (unturned elements) and line ends snap to the slide's edges and middle, the guides when shown (25 / 50 / 75 %), and other elements' edges and middles, within 8 screen points; a pink line shows what it met. Turning settles on every 15° within 3°.
- The ＋ in the strip and new slides from it go after the current slide — §14-6.
- Slide reordering uses system drag and drop (lift after a hold, brand insertion bar, the scroll view scrolls near its edges).
- Copy / paste of slides is in memory, in the app only; pasting into another deck copies the images over.

## Undo

- Snapshots of the slide array (copy-on-write) with a 100-step limit; drags, pinches and turns are one step from start to end; typing, sliders and color pickers on the same thing within 1 s merge into one step.
- Deck settings (guides, favorite, name) aren't part of undo.

## Player

- Tap in the middle third toggles the controls; right third → next (animation step first), left third → previous; controls hide after 3 s — §14-7. Controls are small and stay inside the safe area.
- The player opens on black without a slide-up, turns the screen, then fades the slide in (and fades out before turning back), so the turn isn't seen.
- A swipe changes slide with every element in its final state; a tap runs the next step — §9.
- A slide's transition is the way into it: forward plays the next slide's; back plays the current slide's in reverse (so coming back to a slide doesn't replay its own). Both slides are drawn during the transition.
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

## Fonts

- The font picker lists families; a family with several weights (ヒラギノ角ゴシック W0–W9, SF Pro…) opens a list of them. The system font's weights are stored as "System-<weight>".
- New text is set in ヒラギノ角ゴシック (HiraginoSans-W3); bold uses its W6.

## Text effects and animations

- Text boxes can have an outline (縁取り) and a shadow on their letters, box-wide; PowerPoint gets them as a:ln and a:outerShdw on each run.
- An element has at most one 登場 and one 退場 (登場 first); more of the same made no sense.
- Format sheets stay at the medium height and scroll inside.
- Every delete action is red.

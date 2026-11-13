import SwiftUI

/// The slides along the bottom, with their numbers, and ＋ at the end. Tap to go to a slide; hold for its menu,
/// or hold and drag to move it. A plain bar (not glass).
struct PageStrip: View {
    @Bindable var editor: DeckEditor

    /// The slide a dragged one would land before; nil past the last.
    @State private var dropTarget: UUID?
    @State private var dropAtEnd = false

    private let width: CGFloat = 100

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(editor.slides.enumerated()), id: \.element.id) { index, slide in
                        thumbnail(slide, index: index)
                            .id(slide.id)
                    }
                    addButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .onChange(of: editor.currentIndex) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo(editor.current.id, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(editor.current.id, anchor: .center) }
        }
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 1 / 3)
        }
        .sensoryFeedback(.selection, trigger: editor.currentIndex)
    }

    private func thumbnail(_ slide: SlideContent, index: Int) -> some View {
        let current = index == editor.currentIndex
        return VStack(spacing: 4) {
            SlideThumbnail(slide: slide, deck: editor.deckID, width: width, cornerRadius: 6)
                .frame(width: width)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(current ? SlidesTheme.brand : Color.clear, lineWidth: 2.5)
                }
            Text("\(index + 1)")
                .font(.system(size: 12, weight: current ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(current ? SlidesTheme.brandText : Color.secondary)
        }
        .overlay(alignment: .leading) {
            // Where a dragged slide would go.
            if dropTarget == slide.id {
                Capsule()
                    .fill(SlidesTheme.brand)
                    .frame(width: 4)
                    .padding(.bottom, 18)
                    .offset(x: -8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editor.show(index)
        }
        .contextMenu {
            Button("このスライドの次に複製", systemImage: "plus.square.on.square") { editor.duplicateSlide(at: index) }
            Button("最後に複製", systemImage: "square.on.square.dashed") { editor.duplicateSlideToEnd(at: index) }
            Button("コピー", systemImage: "doc.on.doc") { editor.copySlide(at: index) }
            Button("貼り付け", systemImage: "doc.on.clipboard") { editor.pasteSlide(after: index) }
                .disabled(!editor.canPaste)
            Button("削除", systemImage: "trash", role: .destructive) { editor.deleteSlide(at: index) }
                .disabled(!editor.canDeleteSlide)
        } preview: {
            SlideThumbnail(slide: slide, deck: editor.deckID, width: 240, cornerRadius: 10)
                .frame(width: 240)
        }
        .draggable(Self.payload(slide.id)) {
            SlideThumbnail(slide: slide, deck: editor.deckID, width: width, cornerRadius: 6)
                .frame(width: width)
                .shadow(radius: 8)
        }
        .dropDestination(for: String.self) { items, _ in
            drop(items, before: index)
        } isTargeted: { targeted in
            if targeted {
                dropTarget = slide.id
            } else if dropTarget == slide.id {
                dropTarget = nil
            }
        }
        .accessibilityLabel("スライド\(index + 1)")
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
    }

    private var addButton: some View {
        Menu {
            ForEach(SlideLayout.allCases) { layout in
                Button(layout.label, systemImage: layout.icon) { editor.addSlide(layout) }
            }
            Divider()
            Button("現在のスライドのコピー", systemImage: "plus.square.on.square") { editor.addCopyOfCurrent() }
            Button("最後のスライドのコピー", systemImage: "square.on.square") { editor.addCopyOfLast() }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(SlidesTheme.brand))
        }
        .accessibilityLabel("スライドを追加")
        .padding(.leading, 4)
        .overlay(alignment: .leading) {
            if dropAtEnd {
                Capsule().fill(SlidesTheme.brand).frame(width: 4, height: 56).offset(x: -6)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            drop(items, before: editor.slides.count)
        } isTargeted: { dropAtEnd = $0 }
    }

    private static let prefix = "slides-slide:"

    private static func payload(_ id: UUID) -> String {
        prefix + id.uuidString
    }

    private func drop(_ items: [String], before index: Int) -> Bool {
        dropTarget = nil
        dropAtEnd = false
        guard let item = items.first, item.hasPrefix(Self.prefix),
              let id = UUID(uuidString: String(item.dropFirst(Self.prefix.count))) else { return false }
        withAnimation(.snappy) { editor.moveSlide(id, before: index) }
        return true
    }
}

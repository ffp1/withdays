import SwiftUI
import UniformTypeIdentifiers

/// Every page of the note in a grid. A tap goes to the page; holding one offers to duplicate or delete it;
/// dragging one moves it.
struct NotePagesSheet: View {
    let noteID: String
    /// The page on screen in the editor.
    let currentID: String?
    var onPick: (String) -> Void

    @Environment(NotesStore.self) private var notes
    @Environment(\.dismiss) private var dismiss
    @State private var dragging: String?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 14, alignment: .top)]

    var body: some View {
        let note = notes.note(noteID)
        let pages = note?.pages ?? []
        VStack(alignment: .leading, spacing: 0) {
            Text("ページ")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.brand)
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 10)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        if let note {
                            cell(page, index, in: note)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .animation(.snappy, value: pages)
            }
        }
        .sensoryFeedback(.selection, trigger: pages.map(\.id))
    }

    private func cell(_ page: NotePage, _ index: Int, in note: Note) -> some View {
        let current = page.id == currentID
        return Button {
            onPick(page.id)
            dismiss()
        } label: {
            VStack(spacing: 6) {
                Image(uiImage: notes.thumbnail(of: page, in: note))
                    .resizable()
                    .aspectRatio(page.size.width / page.size.height, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(current ? Color.brand : Color.primary.opacity(0.12), lineWidth: current ? 2.5 : 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                Text("\(index + 1)")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(current ? Color.brand : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(dragging == page.id ? 0.4 : 1)
        .contextMenu {
            Button("複製", systemImage: "plus.square.on.square") {
                notes.duplicatePage(page.id, in: noteID)
            }
            Button("削除", systemImage: "trash", role: .destructive) {
                delete(page, index, in: note)
            }
        }
        .onDrag {
            dragging = page.id
            return NSItemProvider(object: page.id as NSString)
        }
        .onDrop(of: [.text], delegate: PageDrop(target: page.id, dragging: $dragging) { source, target in
            guard let pages = notes.note(noteID)?.pages,
                  let from = pages.firstIndex(where: { $0.id == source }),
                  let to = pages.firstIndex(where: { $0.id == target }) else { return }
            withAnimation(.snappy) { notes.movePage(in: noteID, from: from, to: to) }
        })
    }

    /// Deleting the page on screen moves the editor to its neighbor first.
    private func delete(_ page: NotePage, _ index: Int, in note: Note) {
        if page.id == currentID {
            if index + 1 < note.pages.count {
                onPick(note.pages[index + 1].id)
            } else if index > 0 {
                onPick(note.pages[index - 1].id)
            }
        }
        notes.deletePage(page.id, from: noteID)
    }
}

/// Moves the dragged page to wherever it's held over.
private struct PageDrop: DropDelegate {
    let target: String
    @Binding var dragging: String?
    let move: (String, String) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        move(dragging, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Text read from a page.
struct NotePageText: Identifiable {
    let text: String
    let id = UUID()
}

/// The text read from a page, to select, copy or share.
struct NotePageTextSheet: View {
    let text: String

    @State private var copied = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("認識した文字")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.brand)
                Spacer()
                ShareLink(item: text) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                Button {
                    UIPasteboard.general.string = text
                    copied += 1
                } label: {
                    Label("コピー", systemImage: "doc.on.doc")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(.glassProminent)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 12)
            ScrollView {
                Text(text)
                    .font(.system(size: 16))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .sensoryFeedback(.success, trigger: copied)
    }
}

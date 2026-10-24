import SwiftUI
import UniformTypeIdentifiers

/// Rises over the day list on a long press in an empty part of the calendar; drag a template onto a day.
struct TemplateTray: View {
    var onClose: () -> Void
    var onAdd: () -> Void
    var onEdit: (EventTemplate) -> Void
    /// True while a template is being dragged, so the outside-tap catcher steps aside for the calendar.
    @Binding var isDragging: Bool

    @Environment(TemplateStore.self) private var templates
    @Environment(CalendarStore.self) private var store
    @State private var dragOffset: CGFloat = 0
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var draggingID: UUID?

    var body: some View {
        VStack(spacing: 8) {
            header
                .contentShape(Rectangle())
                .gesture(swipeToClose)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(templates.templates) { template in
                        chip(template)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
                .animation(.snappy, value: templates.templates.map(\.id))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .offset(y: dragOffset)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 6)
            // The title is centered on the tray itself, independent of the buttons on either side.
            ZStack {
                Text("テンプレート")
                    .font(.system(size: 16, weight: .bold))
                HStack {
                    circleButton("xmark", action: onClose)
                    Spacer()
                    // Select and ＋ (or delete while selecting) share one pill.
                    HStack(spacing: 0) {
                        pillButton(selecting ? "checkmark.circle.fill" : "checkmark.circle") {
                            withAnimation(.snappy) {
                                selecting.toggle()
                                selection.removeAll()
                            }
                        }
                        if selecting {
                            pillButton("trash", tint: .red, action: deleteSelection)
                                .disabled(selection.isEmpty)
                        } else {
                            pillButton("plus", action: onAdd)
                        }
                    }
                    .padding(.horizontal, 4)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func pillButton(_ icon: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }

    private func circleButton(_ icon: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    private func chip(_ template: EventTemplate) -> some View {
        let color = color(for: template)
        return TemplateChip(template: template, color: color, selecting: selecting, selected: selection.contains(template.id))
            .onTapGesture {
                if selecting {
                    if selection.contains(template.id) { selection.remove(template.id) } else { selection.insert(template.id) }
                } else {
                    onEdit(template)
                }
            }
            .onDrag {
                draggingID = template.id
                isDragging = true
                return NSItemProvider(object: TemplateTransfer.payload(template.id) as NSString)
            } preview: {
                // Drag previews render outside the view tree, so no environment lookups in here.
                TemplateChip(template: template, color: color, selecting: false, selected: false)
                    .frame(width: 160)
            }
            // Dragging over another template reorders the tray.
            .onDrop(of: [.plainText], delegate: ReorderDelegate(target: template.id, draggingID: $draggingID, isDragging: $isDragging, templates: templates))
    }

    private func deleteSelection() {
        withAnimation(.snappy) {
            for id in selection { templates.delete(id: id) }
            selection.removeAll()
            selecting = false
        }
    }

    /// Pull the tray down by its header to close it. Global coordinates keep the drag steady while the tray moves.
    private var swipeToClose: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 60 || value.predictedEndTranslation.height > 160 {
                    onClose()
                } else {
                    withAnimation(.snappy(duration: 0.25)) { dragOffset = 0 }
                }
            }
    }

    private func color(for template: EventTemplate) -> Color {
        guard let cgColor = (store.calendar(id: template.draft.calendarID) ?? store.defaultCalendar)?.cgColor else { return .gray }
        return Color(cgColor: cgColor)
    }
}

private struct ReorderDelegate: DropDelegate {
    let target: UUID
    @Binding var draggingID: UUID?
    @Binding var isDragging: Bool
    let templates: TemplateStore

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != target,
              let from = templates.templates.firstIndex(where: { $0.id == draggingID }),
              let to = templates.templates.firstIndex(where: { $0.id == target })
        else { return }
        withAnimation(.snappy) {
            templates.move(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        isDragging = false
        return true
    }
}

private struct TemplateChip: View {
    let template: EventTemplate
    let color: Color
    let selecting: Bool
    let selected: Bool

    private var timeText: String {
        let draft = template.draft
        if draft.isAllDay { return "終日" }
        return "\(Fmt.time(draft.start))～\(Fmt.time(draft.end))"
    }

    var body: some View {
        HStack(spacing: 8) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Color.brand : Color.secondary)
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(template.draft.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(timeText)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

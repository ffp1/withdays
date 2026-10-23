import SwiftUI

/// Rises over the day list on a long press in an empty part of the calendar; drag a template onto a day.
struct TemplateTray: View {
    var onClose: () -> Void
    var onAdd: () -> Void
    var onEdit: (EventTemplate) -> Void

    @Environment(TemplateStore.self) private var templates
    @Environment(CalendarStore.self) private var store
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            header
                .contentShape(Rectangle())
                .gesture(swipeToClose)

            if templates.templates.isEmpty {
                Spacer()
                Text("＋でテンプレートを登録できます")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Text("日付までドラッグすると予定になります")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(templates.templates) { template in
                            let color = color(for: template)
                            TemplateChip(template: template, color: color)
                                .draggable(TemplateTransfer.payload(template.id)) {
                                    // Drag previews render outside the view tree, so no environment lookups in here.
                                    TemplateChip(template: template, color: color)
                                        .frame(width: 160)
                                }
                                .contextMenu {
                                    Button("編集", systemImage: "pencil") { onEdit(template) }
                                    Button("削除", systemImage: "trash", role: .destructive) {
                                        templates.delete(id: template.id)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
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
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)

                Spacer()
                Text("テンプレート")
                    .font(.system(size: 16, weight: .bold))
                Spacer()

                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            .padding(.horizontal, 14)
        }
    }

    /// Pull the tray down by its header to close it.
    private var swipeToClose: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 80 || value.predictedEndTranslation.height > 220 {
                    onClose()
                } else {
                    withAnimation(.snappy) { dragOffset = 0 }
                }
            }
    }

    private func color(for template: EventTemplate) -> Color {
        guard let cgColor = (store.calendar(id: template.draft.calendarID) ?? store.defaultCalendar)?.cgColor else { return .gray }
        return Color(cgColor: cgColor)
    }
}

private struct TemplateChip: View {
    let template: EventTemplate
    let color: Color

    private var timeText: String {
        let draft = template.draft
        if draft.isAllDay { return "終日" }
        return "\(Fmt.time(draft.start))～\(Fmt.time(draft.end))"
    }

    var body: some View {
        HStack(spacing: 8) {
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
    }
}

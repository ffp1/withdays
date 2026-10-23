import EventKit
import SwiftUI

/// Half-height details on long press; pulling it up to full height turns it into the editor.
struct EventDetailSheet: View {
    let event: EKEvent

    @Environment(CalendarStore.self) private var store
    @Environment(TemplateStore.self) private var templates
    @Environment(\.dismiss) private var dismiss

    @State private var detent: PresentationDetent = .medium
    @State private var dateAction: DateAction?
    @State private var pickedDates: [Date] = []
    @State private var pendingAction: DateAction?
    @State private var spanRequest: SpanRequest?
    @State private var confirmDelete = false
    @State private var savedAsTemplate = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if detent == .large {
                EventEditorView(mode: .edit(event))
            } else {
                details
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .sheet(item: $dateAction, onDismiss: applyPickedDates) { action in
            DatePickModal(action: action, initialDate: event.startDate) { dates in
                pendingAction = action
                pickedDates = dates
            }
        }
        .spanDialog($spanRequest)
        .confirmationDialog("この予定を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { run { try store.delete(event) } }
        }
        .errorAlert($errorMessage)
    }

    private var details: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(event.color)
                            .frame(width: 5)
                            .frame(maxHeight: .infinity)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.displayTitle)
                                .font(.system(size: 24, weight: .bold))
                            Text(Fmt.range(start: event.startDate, end: event.endDate, isAllDay: event.isAllDay))
                                .font(.system(size: 15))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            if event.hasRecurrenceRules {
                                Label(Recurrence(rule: event.recurrenceRules?.first).summary, systemImage: "repeat")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    if let location = event.location, !location.isEmpty {
                        infoRow(icon: "mappin.and.ellipse") { Text(location) }
                    }
                    if let url = event.url {
                        infoRow(icon: "link") {
                            Link(url.absoluteString, destination: url)
                                .lineLimit(1)
                        }
                    }
                    if let notes = event.notes, !notes.isEmpty {
                        infoRow(icon: "text.alignleft") { Text(notes) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive, action: requestDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    actionButton("移動", icon: "calendar.badge.clock") { dateAction = .move }
                    actionButton("複製", icon: "plus.square.on.square") { dateAction = .duplicate }
                    actionButton(
                        savedAsTemplate ? "登録しました" : "テンプレートに登録",
                        icon: savedAsTemplate ? "checkmark" : "square.on.square.dashed",
                        action: saveAsTemplate
                    )
                    .disabled(savedAsTemplate)
                }
                .buttonStyle(.glass)
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    private func infoRow<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            content()
                .font(.system(size: 15))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Actions

    /// Everything but the date becomes a template, ready to drag from the tray.
    private func saveAsTemplate() {
        templates.upsert(EventTemplate(draft: EventDraft(event: event)))
        withAnimation { savedAsTemplate = true }
    }

    private func requestDelete() {
        if event.hasRecurrenceRules {
            spanRequest = SpanRequest(message: "くりかえしの予定を削除", destructive: true) { span in
                run { try store.delete(event, span: span) }
            }
        } else {
            confirmDelete = true
        }
    }

    /// Runs after the date modal has closed, so a span question can be shown here.
    private func applyPickedDates() {
        guard let action = pendingAction, !pickedDates.isEmpty else { return }
        let dates = pickedDates
        pendingAction = nil
        pickedDates = []
        switch action {
        case .duplicate:
            run { try store.duplicate(event, to: dates) }
        case .move:
            guard let day = dates.first else { return }
            if event.hasRecurrenceRules {
                spanRequest = SpanRequest(message: "くりかえしの予定を移動") { span in
                    run { try store.move(event, to: day, span: span) }
                }
            } else {
                run { try store.move(event, to: day) }
            }
        }
    }

    private func run(_ work: () throws -> Void) {
        do {
            try work()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

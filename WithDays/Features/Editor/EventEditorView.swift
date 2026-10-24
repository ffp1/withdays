import EventKit
import SwiftUI

enum EditorMode: Identifiable {
    case new
    case edit(EKEvent)
    /// Registering (nil) or editing a template; same form, no dates.
    case template(EventTemplate?)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let event): "edit-\(event.eventIdentifier ?? "")-\(event.startDate.timeIntervalSince1970)"
        case .template(let template): "template-\(template?.id.uuidString ?? "new")"
        }
    }
}

/// Where the title field sits, so the history box can float right under it.
private struct TitleFieldAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

enum EditorPath: Hashable {
    case calendar, newCalendar, repeatRule, monthlyRule
}

/// 「あたらしい予定」「予定の編集」「テンプレートの登録」 share this form.
struct EventEditorView: View {
    let mode: EditorMode

    @Environment(CalendarStore.self) private var store
    @Environment(TemplateStore.self) private var templates
    @Environment(\.dismiss) private var dismiss

    @State private var draft: EventDraft
    @State private var path: [EditorPath] = []
    @State private var spanRequest: SpanRequest?
    @State private var errorMessage: String?
    @State private var titleFocused = false
    /// Filled a moment after typing pauses, so nothing else changes while the keyboard is still composing.
    @State private var suggestions: [EKEvent] = []

    init(mode: EditorMode, day: Date = .now) {
        self.mode = mode
        switch mode {
        case .new:
            _draft = State(initialValue: EventDraft(day: day))
        case .edit(let event):
            _draft = State(initialValue: EventDraft(event: event))
        case .template(let template):
            _draft = State(initialValue: template?.draft ?? EventDraft(day: day))
        }
    }

    private var isTemplate: Bool {
        if case .template = mode { return true }
        return false
    }

    private var editingEvent: EKEvent? {
        if case .edit(let event) = mode { return event }
        return nil
    }

    private var title: String {
        switch mode {
        case .new: "あたらしい予定"
        case .edit: "予定の編集"
        case .template(let template): template == nil ? "テンプレートの登録" : "テンプレートの編集"
        }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedCalendar: EKCalendar? {
        store.calendar(id: draft.calendarID) ?? store.defaultCalendar
    }


    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    IMETextField(
                        placeholder: "タイトル",
                        text: $draft.title,
                        isFocused: $titleFocused,
                        font: .systemFont(ofSize: 17 * 1.2, weight: .bold)
                    )
                    .frame(minHeight: 30)
                    .anchorPreference(key: TitleFieldAnchor.self, value: .bounds) { $0 }
                    NavigationLink(value: EditorPath.calendar) {
                        HStack {
                            Text("カレンダー")
                            Spacer()
                            if let calendar = selectedCalendar {
                                CalendarDot(color: Color(cgColor: calendar.cgColor), size: 9)
                                Text(calendar.title)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Toggle("終日", isOn: $draft.isAllDay.animation())
                    if !(isTemplate && draft.isAllDay) {
                        DatePicker("開始", selection: startBinding, displayedComponents: dateComponents)
                        DatePicker("終了", selection: $draft.end, in: draft.start..., displayedComponents: dateComponents)
                    }
                    NavigationLink(value: EditorPath.repeatRule) {
                        LabeledContent("くりかえし", value: draft.recurrence.summary)
                    }
                }

                Section {
                    TextField("場所", text: $draft.location)
                    TextField("URL", text: $draft.url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("メモ", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...)
                }
            }
            .overlayPreferenceValue(TitleFieldAnchor.self) { anchor in
                // History floats just under the title field, over the rest of the form.
                GeometryReader { geo in
                    let list = suggestions
                    if let anchor, !list.isEmpty {
                        let field = geo[anchor]
                        suggestionBox(list)
                            .frame(width: field.width + 24)
                            .offset(x: field.minX - 12, y: field.maxY + 10)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Never disabled: flipping it while typing commits the first character of Japanese input.
                    Button(action: save) { Image(systemName: "checkmark") }
                        .buttonStyle(.glassProminent)
                        .tint(.brand)
                }
            }
            .navigationDestination(for: EditorPath.self) { route in
                switch route {
                case .calendar:
                    CalendarPickerView(selectedID: selectedCalendar?.calendarIdentifier) { id in
                        draft.calendarID = id
                        path.removeAll()
                    }
                case .newCalendar:
                    NewCalendarView { id in
                        draft.calendarID = id
                        path.removeAll()
                    }
                case .repeatRule:
                    RepeatView(recurrence: $draft.recurrence) { path.append(.monthlyRule) }
                case .monthlyRule:
                    MonthlyRuleView(recurrence: $draft.recurrence)
                }
            }
        }
        .task {
            if draft.calendarID == nil { draft.calendarID = store.defaultCalendar?.calendarIdentifier }
            if case .new = mode {
                try? await Task.sleep(for: .milliseconds(400))
                titleFocused = true
            }
        }
        .task(id: draft.title) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            suggestions = titleFocused ? store.history(matching: draft.title, limit: 5) : []
        }
        .onChange(of: titleFocused) { _, focused in
            if !focused { suggestions = [] }
        }
        .spanDialog($spanRequest)
        .errorAlert($errorMessage)
    }

    /// Moving the start keeps the length by moving the end with it.
    private var startBinding: Binding<Date> {
        Binding(
            get: { draft.start },
            set: { new in
                draft.end = draft.end.addingTimeInterval(new.timeIntervalSince(draft.start))
                draft.start = new
            }
        )
    }

    private var dateComponents: DatePickerComponents {
        if isTemplate { return [.hourAndMinute] }
        return draft.isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(action: save) {
                Text("保存")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)

            if editingEvent != nil {
                Button(role: .destructive, action: requestDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(6)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func suggestionBox(_ events: [EKEvent]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                if index > 0 { Divider().padding(.leading, 32) }
                Button { applySuggestion(event) } label: {
                    suggestionRow(event)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
    }

    private func suggestionRow(_ event: EKEvent) -> some View {
        HStack(spacing: 10) {
            CalendarDot(color: event.color, size: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.displayTitle)
                    .foregroundStyle(.primary)
                Text(Fmt.fullDate(event.startDate))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions

    /// Copies everything but the date from a past event.
    private func applySuggestion(_ event: EKEvent) {
        let copied = EventDraft(event: event).placed(on: draft.start)
        titleFocused = false
        suggestions = []
        draft = copied
    }

    private func save() {
        guard canSave else { return }
        switch mode {
        case .template(let template):
            templates.upsert(EventTemplate(id: template?.id ?? UUID(), draft: draft))
            dismiss()
        case .new:
            run { try store.save(draft) }
        case .edit(let event):
            if event.hasRecurrenceRules {
                spanRequest = SpanRequest(message: "くりかえしの予定を保存") { span in
                    run { try store.save(draft, to: event, span: span) }
                }
            } else {
                run { try store.save(draft, to: event) }
            }
        }
    }

    private func requestDelete() {
        guard let event = editingEvent else { return }
        if event.hasRecurrenceRules {
            spanRequest = SpanRequest(message: "くりかえしの予定を削除", destructive: true) { deleteEvent(span: $0) }
        } else {
            // No confirmation: the toast on the home screen can undo it.
            deleteEvent(span: .thisEvent)
        }
    }

    private func deleteEvent(span: EKSpan) {
        guard let event = editingEvent else { return }
        run { try store.delete(event, span: span) }
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

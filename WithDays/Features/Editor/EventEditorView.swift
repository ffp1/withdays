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
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

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

    private var suggestions: [EKEvent] {
        guard titleFocused else { return [] }
        return store.history(matching: draft.title)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    TextField("タイトル", text: $draft.title)
                        .font(.system(size: 17 * 1.2))
                        .focused($titleFocused)
                        .submitLabel(.done)
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

                if !suggestions.isEmpty {
                    Section("履歴") {
                        ForEach(suggestions, id: \.self) { event in
                            Button { applySuggestion(event) } label: { suggestionRow(event) }
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
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .disabled(!canSave)
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
        .spanDialog($spanRequest)
        .confirmationDialog("この予定を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { deleteEvent(span: .thisEvent) }
        }
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
            .disabled(!canSave)

            if editingEvent != nil {
                Button(role: .destructive, action: requestDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(6)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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
            confirmDelete = true
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

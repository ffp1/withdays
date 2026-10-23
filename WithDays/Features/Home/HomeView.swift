import EventKit
import SwiftUI

enum HomeRoute: Hashable {
    case search, settings
}

struct HomeView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(TemplateStore.self) private var templates

    /// Pages are month offsets from the month the app launched in.
    private static let pageRange = -600...600
    private let baseMonth = CalendarMath.startOfMonth(.now)

    @State private var page: Int?
    @State private var selectedDate: Date
    @State private var path: [HomeRoute] = []
    @State private var showMonthPicker = false
    @State private var editor: EditorMode?
    @State private var detail: EventRef?
    @State private var showTemplates = false
    @State private var spanRequest: SpanRequest?
    @State private var errorMessage: String?
    @State private var todayPulse = 0

    init() {
        let stored = UserDefaults.standard.double(forKey: SettingsKey.lastMonth)
        let month = stored > 0 ? CalendarMath.startOfMonth(Date(timeIntervalSince1970: stored)) : CalendarMath.startOfMonth(.now)
        let offset = CalendarMath.months(from: .now, to: month)
        _page = State(initialValue: Self.pageRange.contains(offset) ? offset : 0)
        _selectedDate = State(initialValue: CalendarMath.defaultSelection(in: month))
    }

    private var displayedMonth: Date {
        CalendarMath.addMonths(page ?? 0, to: baseMonth)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                monthPager
                dayBand
                ZStack(alignment: .bottom) {
                    DayEventList(
                        day: selectedDate,
                        onEdit: { editor = .edit($0) },
                        onDelete: delete,
                        onAdd: { editor = .new }
                    )
                    if showTemplates {
                        TemplateTray(
                            onClose: { withAnimation(.snappy) { showTemplates = false } },
                            onAdd: { editor = .template(nil) },
                            onEdit: { editor = .template($0) }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if !showTemplates {
                    HStack {
                        thisMonthButton
                        Spacer()
                        addButton
                    }
                    .padding(20)
                }
            }
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .search:
                    SearchView { date in
                        jump(to: date)
                        selectedDate = CalendarMath.startOfDay(date)
                        path.removeAll()
                    }
                case .settings:
                    SettingsView()
                }
            }
        }
        .sheet(isPresented: $showMonthPicker) {
            MonthPickerSheet(selected: displayedMonth) { jump(to: $0) }
                .presentationDetents([.medium])
        }
        .sheet(item: $editor) { mode in
            EventEditorView(mode: mode, day: selectedDate)
        }
        .sheet(item: $detail) { ref in
            EventDetailSheet(event: ref.event)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: detail?.id) { _, new in new != nil }
        .sensoryFeedback(.impact(weight: .medium), trigger: showTemplates) { _, new in new }
        .sensoryFeedback(.impact(weight: .heavy), trigger: todayPulse)
        .spanDialog($spanRequest)
        .errorAlert($errorMessage)
        .onOpenURL(perform: open)
    }

    // MARK: Pieces

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showMonthPicker = true
            } label: {
                HStack(spacing: 4) {
                    Text(Fmt.monthTitle(displayedMonth))
                        .font(.system(size: 20, weight: .bold))
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(.primary)
                .fixedSize()
            }
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationLink(value: HomeRoute.search) {
                Image(systemName: "magnifyingglass")
            }
            NavigationLink(value: HomeRoute.settings) {
                Image(systemName: "gearshape")
            }
        }
    }

    private var monthPager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Self.pageRange, id: \.self) { offset in
                    MonthGridView(
                        month: CalendarMath.addMonths(offset, to: baseMonth),
                        selectedDate: $selectedDate,
                        onEventLongPress: { detail = EventRef(event: $0) },
                        onEmptyLongPress: { day in
                            selectedDate = day
                            withAnimation(.snappy) { showTemplates = true }
                        },
                        onDayDoubleTap: { day in
                            selectedDate = day
                            editor = .new
                        },
                        onTemplateDrop: dropTemplate
                    )
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $page)
        .frame(height: GridMetrics.height)
        .environment(\.todayPulse, todayPulse)
        .sensoryFeedback(.selection, trigger: selectedDate)
        .sensoryFeedback(.impact(weight: .light), trigger: page)
        .onChange(of: page) { _, _ in
            // The selected day stays as it is when the month changes.
            UserDefaults.standard.set(displayedMonth.timeIntervalSince1970, forKey: SettingsKey.lastMonth)
        }
    }

    private var dayBand: some View {
        let holiday = store.holidayName(on: selectedDate)
        return HStack(spacing: 8) {
            Text(Fmt.fullDate(selectedDate))
                .monospacedDigit()
            if let holiday {
                Text(holiday)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.dayNumber(weekday: CalendarMath.weekday(selectedDate), isHoliday: holiday != nil))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    private var addButton: some View {
        Button {
            editor = .new
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26.4, weight: .semibold))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
    }

    private var thisMonthButton: some View {
        Button(action: backToThisMonth) {
            Image(systemName: "arrow.uturn.left")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    // MARK: Actions

    /// Scrolls to the month of `date`; the selected day is left alone.
    private func jump(to date: Date) {
        let offset = CalendarMath.months(from: baseMonth, to: date)
        scroll(to: min(max(offset, Self.pageRange.lowerBound), Self.pageRange.upperBound))
    }

    /// Jumps next to `target` without animation, then animates only the last month.
    private func scroll(to target: Int) {
        let current = page ?? 0
        guard target != current else { return }
        if abs(target - current) > 1 {
            page = target + (target > current ? -1 : 1)
            Task { @MainActor in
                withAnimation(.snappy) { page = target }
            }
        } else {
            withAnimation(.snappy) { page = target }
        }
    }

    private func backToThisMonth() {
        let today = CalendarMath.startOfDay(.now)
        if page == 0, CalendarMath.isSameDay(selectedDate, today) {
            // Already there: make today's number speak up instead.
            todayPulse += 1
            return
        }
        scroll(to: 0)
        selectedDate = today
    }

    /// A day tapped in the widget: close whatever is open and focus that day.
    private func open(_ url: URL) {
        guard let day = DeepLink.day(from: url) else { return }
        path.removeAll()
        editor = nil
        detail = nil
        showMonthPicker = false
        withAnimation(.snappy) { showTemplates = false }
        jump(to: day)
        selectedDate = day
    }

    private func delete(_ event: EKEvent) {
        let run: (EKSpan) -> Void = { span in
            do { try store.delete(event, span: span) } catch { errorMessage = error.localizedDescription }
        }
        if event.hasRecurrenceRules {
            spanRequest = SpanRequest(message: "くりかえしの予定を削除", destructive: true, perform: run)
        } else {
            run(.thisEvent)
        }
    }

    private func dropTemplate(_ id: UUID, on day: Date) {
        guard let template = templates.template(id: id) else { return }
        do {
            try store.save(template.draft.placed(on: day))
            selectedDate = day
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

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
                        onDelete: delete
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
        .spanDialog($spanRequest)
        .errorAlert($errorMessage)
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
        .sensoryFeedback(.selection, trigger: selectedDate)
        .onChange(of: page) { _, _ in
            UserDefaults.standard.set(displayedMonth.timeIntervalSince1970, forKey: SettingsKey.lastMonth)
            if !CalendarMath.isSameMonth(selectedDate, displayedMonth) {
                selectedDate = CalendarMath.defaultSelection(in: displayedMonth)
            }
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
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
    }

    private var thisMonthButton: some View {
        Button(action: backToThisMonth) {
            Text("今月")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    // MARK: Actions

    private func jump(to date: Date) {
        let offset = CalendarMath.months(from: baseMonth, to: date)
        page = min(max(offset, Self.pageRange.lowerBound), Self.pageRange.upperBound)
        selectedDate = CalendarMath.defaultSelection(in: CalendarMath.startOfMonth(date))
    }

    private func backToThisMonth() {
        let today = CalendarMath.startOfDay(.now)
        // Scroll smoothly from nearby months; jump straight from far away.
        if abs(page ?? 0) <= 2 {
            withAnimation(.snappy) { page = 0 }
        } else {
            page = 0
        }
        selectedDate = today
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

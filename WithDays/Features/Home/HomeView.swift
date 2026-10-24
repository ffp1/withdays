import EventKit
import SwiftUI

enum HomeRoute: Hashable {
    case search, settings
}

enum HomeMode: String {
    case calendar, todo
}

struct HomeView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(TemplateStore.self) private var templates
    /// Plain state (saved on change) so switching can animate; @AppStorage updates don't carry the animation.
    @State private var mode = UserDefaults.standard.string(forKey: SettingsKey.homeMode) ?? HomeMode.calendar.rawValue

    /// Pages are month offsets from the month the app launched in.
    private static let pageRange = -600...600
    private let baseMonth = CalendarMath.startOfMonth(.now)

    @State private var page: Int?
    /// During a long jump the neighbouring page temporarily shows the target month, so the scroll covers one page.
    @State private var pageMonths: [Int: Int] = [:]
    @State private var selectedDate: Date
    @State private var path: [HomeRoute] = []
    @State private var showMonthPicker = false
    @State private var editor: EditorMode?
    @State private var detail: EventRef?
    @State private var showTemplates = false
    @State private var trayDragging = false
    @State private var listHeight: CGFloat = 300
    @State private var relocation: Relocation?
    @State private var toast: CalendarStore.DeletedEvent?
    @State private var lastDoubleTap = Date.distantPast
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

    private var isTodo: Bool { mode == HomeMode.todo.rawValue }

    private var displayedMonth: Date {
        let id = page ?? 0
        return CalendarMath.addMonths(pageMonths[id] ?? id, to: baseMonth)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                if isTodo {
                    TodoView()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                } else {
                    calendarContent
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .animation(.snappy(duration: 0.35), value: mode)
            .onChange(of: mode) { _, new in UserDefaults.standard.set(new, forKey: SettingsKey.homeMode) }
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
        .overlay(alignment: .bottom) { trayLayer }
        .overlay(alignment: .bottom) { toastLayer }
        .sheet(isPresented: $showMonthPicker) {
            MonthPickerSheet(selected: displayedMonth) { jump(to: $0) }
                .presentationDetents([.medium])
        }
        .sheet(item: $editor) { mode in
            EventEditorView(mode: mode, day: selectedDate)
        }
        .sheet(item: $detail) { ref in
            EventDetailSheet(event: ref.event) { kind in startRelocation(ref.event, kind) }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: detail?.id) { _, new in new != nil }
        .sensoryFeedback(.impact(weight: .medium), trigger: showTemplates) { _, new in new }
        .sensoryFeedback(.impact(weight: .heavy), trigger: todayPulse)
        .sensoryFeedback(.success, trigger: toast?.id) { _, new in new != nil }
        .onChange(of: path) { _, new in if !new.isEmpty { closeTray() } }
        .onChange(of: showMonthPicker) { _, shown in if shown { closeTray() } }
        .onChange(of: store.lastDeleted?.id) { _, _ in showToast() }
        .spanDialog($spanRequest)
        .errorAlert($errorMessage)
        .onOpenURL(perform: open)
    }

    // MARK: Calendar

    private var calendarContent: some View {
        VStack(spacing: 0) {
            monthPager
            dayBand
            DayEventList(
                day: selectedDate,
                onEdit: { openEditor(.edit($0)) },
                onDelete: delete,
                onRelocate: startRelocation,
                onAdd: { openEditor(.new) },
                onSwipeDay: { delta in
                    let day = CalendarMath.addDays(delta, to: selectedDate)
                    selectedDate = day
                    if !CalendarMath.isSameMonth(day, displayedMonth) { jump(to: day) }
                }
            )
            .allowsHitTesting(relocation == nil)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        }
        .overlay(alignment: .bottom) {
            HStack {
                if relocation != nil {
                    circleButton("xmark", prominent: false, action: cancelRelocation)
                } else {
                    circleButton("arrow.uturn.left", prominent: false, action: backToThisMonth)
                }
                Spacer()
                if relocation != nil {
                    circleButton("checkmark", prominent: true, action: confirmRelocation)
                        .disabled(relocation?.targets.isEmpty ?? true)
                } else {
                    circleButton("plus", prominent: true) { openEditor(.new) }
                }
            }
            .padding(20)
            .opacity(showTemplates ? 0 : 1)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isTodo {
                Text("ToDo")
                    .font(.system(size: 20, weight: .bold))
                    .fixedSize()
                    .transition(.blurReplace)
            } else {
                Button {
                    showMonthPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(Fmt.monthTitle(displayedMonth))
                            .font(.system(size: 20, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(page ?? 0)))
                            .animation(.snappy, value: page)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.primary)
                    .fixedSize()
                }
            }
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                withAnimation(.snappy) {
                    closeTray()
                    relocation = nil
                    mode = isTodo ? HomeMode.calendar.rawValue : HomeMode.todo.rawValue
                }
            } label: {
                Image(systemName: isTodo ? "calendar" : "checkmark.circle")
                    .contentTransition(.symbolEffect(.replace))
            }
            if !isTodo {
                NavigationLink(value: HomeRoute.search) {
                    Image(systemName: "magnifyingglass")
                }
            }
            NavigationLink(value: HomeRoute.settings) {
                Image(systemName: "gearshape")
            }
        }
    }

    private var monthPager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Self.pageRange, id: \.self) { id in
                    MonthGridView(
                        month: CalendarMath.addMonths(pageMonths[id] ?? id, to: baseMonth),
                        selectedDate: selectedDate,
                        relocation: relocation,
                        actions: gridActions
                    )
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $page)
        .scrollDisabled(relocation != nil)
        .frame(height: GridMetrics.height)
        .environment(\.todayPulse, todayPulse)
        .sensoryFeedback(.selection, trigger: selectedDate)
        .sensoryFeedback(.impact(weight: .light), trigger: page)
        .onChange(of: page) { _, _ in
            // The selected day stays as it is when the month changes.
            UserDefaults.standard.set(displayedMonth.timeIntervalSince1970, forKey: SettingsKey.lastMonth)
        }
    }

    private var gridActions: GridActions {
        GridActions(
            onDayTap: { selectedDate = $0 },
            onDayDoubleTap: { day in
                lastDoubleTap = .now
                selectedDate = day
                openEditor(.new)
            },
            onDayLongPress: { day in
                selectedDate = day
                withAnimation(.snappy) { showTemplates = true }
            },
            onEventTap: eventTapped,
            onEventLongPress: openDetail,
            onTemplateDrop: dropTemplate,
            onTargetTap: { day in updateTargets(day, painting: false) },
            onTargetDrag: { day in updateTargets(day, painting: true) }
        )
    }

    private var dayBand: some View {
        let holiday = store.holidayName(on: selectedDate)
        return HStack(spacing: 8) {
            Text(Fmt.fullDate(selectedDate))
                .monospacedDigit()
                .contentTransition(.numericText(value: selectedDate.timeIntervalSince1970))
            if let holiday {
                Text(holiday)
                    .transition(.opacity)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.dayNumber(weekday: CalendarMath.weekday(selectedDate), isHoliday: holiday != nil))
        .animation(.snappy, value: selectedDate)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private func circleButton(_ icon: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        let label = Image(systemName: icon)
            .font(.system(size: prominent ? 26.4 : 24, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(width: 56, height: 56)
        if prominent {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
        } else {
            Button(action: action) { label }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        }
    }

    /// The template tray sits over the day list; a tap anywhere else closes it and is not passed through.
    @ViewBuilder
    private var trayLayer: some View {
        if showTemplates, !isTodo {
            ZStack(alignment: .bottom) {
                if !trayDragging {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { closeTray() }
                }
                TemplateTray(
                    onClose: closeTray,
                    onAdd: { editor = .template(nil) },
                    onEdit: { editor = .template($0) },
                    isDragging: $trayDragging
                )
                .frame(height: listHeight)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// While the toast shows, nothing else reacts to touches.
    @ViewBuilder
    private var toastLayer: some View {
        if toast != nil {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                HStack(spacing: 12) {
                    Text("予定を削除しました")
                        .font(.system(size: 14, weight: .semibold))
                    Button("元に戻す", action: undoDelete)
                        .font(.system(size: 14, weight: .bold))
                        .underline()
                        .foregroundStyle(Color.brand)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 16)
                .frame(height: 56)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 20 + 56 + 10)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Actions

    private func openEditor(_ mode: EditorMode) {
        closeTray()
        editor = mode
    }

    private func openDetail(_ event: EKEvent) {
        closeTray()
        detail = EventRef(event: event)
    }

    private func closeTray() {
        guard showTemplates else { return }
        withAnimation(.snappy(duration: 0.25)) { showTemplates = false }
        trayDragging = false
    }

    /// On the already selected day a single tap opens the event; a double tap (new event) still wins.
    private func eventTapped(_ event: EKEvent, on day: Date) {
        guard CalendarMath.isSameDay(day, selectedDate) else {
            selectedDate = day
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard Date.now.timeIntervalSince(lastDoubleTap) > 0.45 else { return }
            openDetail(event)
        }
    }

    /// Scrolls to the month of `date`; the selected day is left alone.
    private func jump(to date: Date) {
        let offset = CalendarMath.months(from: baseMonth, to: date)
        scroll(to: min(max(offset, Self.pageRange.lowerBound), Self.pageRange.upperBound))
    }

    /// For a jump of more than one month, the page next to the current one shows the target month,
    /// the pager scrolls that single page, then it silently swaps to the target's real page.
    private func scroll(to target: Int) {
        let current = page ?? 0
        guard target != current else { return }
        guard abs(target - current) > 1 else {
            withAnimation(.snappy) { page = target }
            return
        }
        let neighbor = current + (target > current ? 1 : -1)
        pageMonths = [neighbor: target]
        withAnimation(.snappy(duration: 0.35)) { page = neighbor }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                page = target
                pageMonths = [:]
            }
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

    /// Widget links: withdays://day/<date> focuses that day, withdays://todo opens ToDo.
    private func open(_ url: URL) {
        path.removeAll()
        editor = nil
        detail = nil
        showMonthPicker = false
        closeTray()
        relocation = nil
        if url.host == "todo" {
            mode = HomeMode.todo.rawValue
            return
        }
        guard let day = DeepLink.day(from: url) else { return }
        mode = HomeMode.calendar.rawValue
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

    private func showToast() {
        guard let deleted = store.lastDeleted else { return }
        withAnimation(.snappy) { toast = deleted }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard toast?.id == deleted.id else { return }
            withAnimation(.snappy) { toast = nil }
            store.clearLastDeleted(deleted.id)
        }
    }

    private func undoDelete() {
        do { try store.undoDelete() } catch { errorMessage = error.localizedDescription }
        withAnimation(.snappy) { toast = nil }
    }

    private func dropTemplate(_ id: UUID, on day: Date) {
        trayDragging = false
        guard let template = templates.template(id: id) else { return }
        do {
            try store.save(template.draft.placed(on: day))
            selectedDate = day
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Move / duplicate on the calendar

    private func startRelocation(_ event: EKEvent, _ kind: RelocationKind) {
        closeTray()
        withAnimation(.snappy) { relocation = Relocation(event: event, kind: kind) }
    }

    /// Move keeps one target; duplicate toggles on tap and adds while painting.
    private func updateTargets(_ day: Date, painting: Bool) {
        guard var next = relocation else { return }
        switch next.kind {
        case .move:
            next.targets = [day]
        case .duplicate:
            if painting {
                next.targets.insert(day)
            } else if next.targets.contains(day) {
                next.targets.remove(day)
            } else {
                next.targets.insert(day)
            }
        }
        if next != relocation {
            withAnimation(.snappy(duration: 0.2)) { relocation = next }
        }
    }

    private func cancelRelocation() {
        withAnimation(.snappy) { relocation = nil }
    }

    private func confirmRelocation() {
        guard let current = relocation, !current.targets.isEmpty else { return }
        withAnimation(.snappy) { relocation = nil }
        let event = current.event
        switch current.kind {
        case .duplicate:
            do { try store.duplicate(event, to: current.targets.sorted()) } catch { errorMessage = error.localizedDescription }
        case .move:
            guard let day = current.targets.first else { return }
            let run: (EKSpan) -> Void = { span in
                do { try store.move(event, to: day, span: span) } catch { errorMessage = error.localizedDescription }
            }
            if event.hasRecurrenceRules {
                spanRequest = SpanRequest(message: "くりかえしの予定を移動", perform: run)
            } else {
                run(.thisEvent)
            }
        }
        selectedDate = current.targets.sorted().first ?? selectedDate
    }
}

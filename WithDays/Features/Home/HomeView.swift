import EventKit
import SwiftUI

enum HomeRoute: Hashable {
    case search, settings
}

enum HomeMode: String {
    case calendar, todo, go, mo
}

struct HomeView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(TemplateStore.self) private var templates
    @Environment(ToastCenter.self) private var toasts
    /// Plain state (saved on change) so switching can animate; @AppStorage updates don't carry the animation.
    @State private var mode = UserDefaults.standard.string(forKey: SettingsKey.homeMode) ?? HomeMode.calendar.rawValue

    /// Pages are month offsets from the month the app launched in.
    private static let pageRange = -600...600
    private let baseMonth = CalendarMath.startOfMonth(.now)

    @State private var page: Int?
    /// The day the list below the calendar shows; it trails `selectedDate` while a slide runs.
    @State private var listDay: Date
    @State private var dayPager = PagerModel<Date>()
    /// Set when a double tap lands while an event sheet is opening: close it, then open a new event.
    @State private var newEventAfterDetail = false
    /// Holding ＋ floats the Mo / Go menu; sliding onto one and letting go opens it.
    @State private var fabMenuShown = false
    @State private var fabHover: HomeMode?
    @State private var fabMenuFrames: [HomeMode: CGRect] = [:]
    @State private var fabFrame: CGRect = .zero
    /// Where the finger is while the menu is up; letting go on ＋ itself adds an event as a tap would.
    @State private var fabPoint: CGPoint?
    @State private var fabLongPressed = false
    /// True while a finger is down on ＋; the hold's progress (0–1) turns ＋ into × and dims the screen.
    @GestureState private var fabPressing = false
    @State private var fabPress: CGFloat = 0
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
    @State private var spanRequest: SpanRequest?
    @State private var errorMessage: String?
    @State private var todayPulse = 0

    init() {
        let stored = UserDefaults.standard.double(forKey: SettingsKey.lastMonth)
        let month = stored > 0 ? CalendarMath.startOfMonth(Date(timeIntervalSince1970: stored)) : CalendarMath.startOfMonth(.now)
        let offset = CalendarMath.months(from: .now, to: month)
        _page = State(initialValue: Self.pageRange.contains(offset) ? offset : 0)
        let selection = CalendarMath.defaultSelection(in: month)
        _selectedDate = State(initialValue: selection)
        _listDay = State(initialValue: selection)
    }

    private var isTodo: Bool { mode == HomeMode.todo.rawValue }
    private var isGo: Bool { mode == HomeMode.go.rawValue }
    private var isMo: Bool { mode == HomeMode.mo.rawValue }

    private var displayedMonth: Date {
        let id = page ?? 0
        return CalendarMath.addMonths(pageMonths[id] ?? id, to: baseMonth)
    }

    /// The screen for the current mode; split out so the body type-checks in reasonable time.
    private var modeContent: some View {
        ZStack {
            if isMo {
                MoView {
                    withAnimation(.snappy) { mode = HomeMode.calendar.rawValue }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if isGo {
                GoView {
                    withAnimation(.snappy) { mode = HomeMode.calendar.rawValue }
                }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if isTodo {
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
    }

    /// The navigation stack around the mode's screen, apart from the body to keep type-checking quick.
    private var navigation: some View {
        NavigationStack(path: $path) {
            modeContent
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
    }

    /// The layers over the navigation stack: the template tray, the toast and the ＋ menu.
    private var layered: some View {
        navigation
            .overlay(alignment: .bottom) { trayLayer }
            .overlay(alignment: .bottom) { toastLayer }
            .overlay { fabMenuLayer }
            .sensoryFeedback(.impact(weight: .medium), trigger: fabMenuShown) { (_: Bool, new: Bool) in new }
            .sensoryFeedback(.selection, trigger: fabHover) { (_: HomeMode?, new: HomeMode?) in new != nil }
    }

    /// The calendar's sheets: month picker, editor and event detail.
    private var withSheets: some View {
        layered
            .sheet(isPresented: $showMonthPicker) {
                MonthPickerSheet(selected: displayedMonth) { jump(to: $0) }
                    .presentationDetents([.medium])
            }
            .sheet(item: $editor) { mode in
                EventEditorView(mode: mode, day: selectedDate)
            }
            .sheet(item: $detail, onDismiss: {
                if newEventAfterDetail {
                    newEventAfterDetail = false
                    editor = .new
                }
            }) { ref in
                EventDetailSheet(event: ref.event) { kind in startRelocation(ref.event, kind) }
            }
    }

    var body: some View {
        withSheets
            .sensoryFeedback(.impact(weight: .medium), trigger: detail?.id) { _, new in new != nil }
            .sensoryFeedback(.impact(weight: .medium), trigger: showTemplates) { _, new in new }
            .sensoryFeedback(.impact(weight: .heavy), trigger: todayPulse)
            .sensoryFeedback(.impact(weight: .medium), trigger: store.lastDeleted?.id) { _, new in new != nil }
            .onChange(of: path) { _, new in if !new.isEmpty { closeTray() } }
            .onChange(of: showMonthPicker) { _, shown in if shown { closeTray() } }
            .onChange(of: store.lastDeleted?.id) { _, _ in showToast() }
            .onChange(of: selectedDate) { _, new in
                // Picked on the calendar (not swiped): slide the list there with a quick, sharp ease-out,
                // one page wide however far the day is.
                let day = CalendarMath.startOfDay(new)
                // A swipe already sliding there selected it itself.
                guard !CalendarMath.isSameDay(day, listDay), dayPager.target != day else { return }
                dayPager.slide(to: day, side: day > listDay ? 1 : -1, animation: .timingCurve(0.16, 1, 0.3, 1, duration: 0.3)) {
                    listDay = $0
                }
            }
            .spanDialog($spanRequest)
            .errorAlert($errorMessage)
            .onOpenURL(perform: open)
    }

    // MARK: Calendar

    private var calendarContent: some View {
        GeometryReader { geo in
            // While moving / duplicating, the day list goes away and the calendar takes its space,
            // leaving room for the bottom buttons.
            let expanded = relocation != nil
            let pagerHeight = expanded ? max(GridMetrics.height, geo.size.height - 56 - 20 - 12) : GridMetrics.height
            VStack(spacing: 0) {
                monthPager
                    .frame(height: pagerHeight)
                    .environment(\.gridRowHeight, (pagerHeight - GridMetrics.weekdayHeight) / 6)
                if !expanded {
                    Group {
                        dayBand
                        dayPagerView
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 10) {
                // The same two buttons change their symbols, so the switch animates.
                circleButton(relocation != nil ? "xmark" : "arrow.uturn.left", prominent: false) {
                    if relocation != nil { cancelRelocation() } else { backToThisMonth() }
                }
                if let relocation {
                    Text(relocation.kind == .move ? "移動先を選択" : "複製先を選択")
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .glassEffect(.regular, in: .capsule)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else {
                    Spacer()
                }
                circleButton(relocation != nil ? "checkmark" : "plus", prominent: true) {
                    if relocation != nil {
                        confirmRelocation()
                    } else if fabLongPressed {
                        // The long press opened the menu; the release must not also add an event.
                        fabLongPressed = false
                    } else {
                        openEditor(.new)
                    }
                }
                .disabled(relocation?.targets.isEmpty ?? false)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { fabFrame = $0 }
                .onChange(of: fabPressing) { _, pressing in
                    // Starts a moment after touch-down, so a plain tap doesn't flash it.
                    if pressing, !fabMenuShown {
                        withAnimation(.easeIn(duration: 0.4).delay(0.1)) { fabPress = 1 }
                    } else if !pressing {
                        withAnimation(.easeOut(duration: 0.2)) { fabPress = 0 }
                    }
                }
                // Holding ＋ floats Mo / Go above it; slide onto one and let go to open it.
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                        .updating($fabPressing) { _, pressing, _ in pressing = relocation == nil }
                        .onChanged { value in
                            guard relocation == nil, case .second(true, let drag) = value else { return }
                            if !fabMenuShown {
                                fabLongPressed = true
                                closeTray()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { fabMenuShown = true }
                            }
                            if let drag {
                                fabPoint = drag.location
                                fabHover = fabMenuItem(at: drag.location)
                            }
                        }
                        .onEnded { _ in
                            guard fabMenuShown else { return }
                            let target = fabHover
                            // Not moved at all, or let go on ＋: a new event, as if it had been tapped.
                            let onFab = fabPoint.map { fabFrame.insetBy(dx: -8, dy: -8).contains($0) } ?? true
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                fabMenuShown = false
                                fabHover = nil
                                fabPress = 0
                            }
                            fabPoint = nil
                            if let target {
                                withAnimation(.snappy(duration: 0.35)) { mode = target.rawValue }
                            } else if onFab {
                                openEditor(.new)
                            }
                            // The button may or may not see the release; don't let the flag eat a later tap.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { fabLongPressed = false }
                        }
                )
            }
            .padding(20)
            .opacity(showTemplates ? 0 : 1)
        }
    }

    /// The day list pages sideways; only the add row, the empty space and the date band drag it,
    /// so the rows keep their own swipe actions.
    private var dayPagerView: some View {
        SlidingPager(
            model: dayPager,
            slots: dayPager.slots(
                current: listDay,
                previous: CalendarMath.addDays(-1, to: listDay),
                next: CalendarMath.addDays(1, to: listDay)
            )
        ) { day, _ in
            DayEventList(
                day: day,
                onEdit: { openEditor(.edit($0)) },
                onDelete: delete,
                onRelocate: startRelocation,
                onAdd: { openEditor(.new) },
                onPageDrag: dragDay,
                onPageDragEnd: endDayDrag
            )
        }
    }

    private func dragDay(_ value: DragGesture.Value) {
        dayPager.drag(value, hasPrevious: true, hasNext: true)
    }

    private func endDayDrag(_ value: DragGesture.Value) {
        dayPager.end(
            value,
            previous: CalendarMath.addDays(-1, to: listDay),
            next: CalendarMath.addDays(1, to: listDay),
            onStart: { day in
                // Select as the slide starts, like the month pager does, so the band rolls with it.
                withAnimation(.snappy) { selectedDate = day }
                if !CalendarMath.isSameMonth(day, displayedMonth) { jump(to: day) }
            },
            commit: { listDay = $0 }
        )
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            // Go keeps a clean screen; its calendar button is in the presets sheet.
            if isTodo {
                Text("ToDo")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.brand)
                    .fixedSize()
                    .transition(.blurReplace)
            } else if !isGo, !isMo {
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
            // Go keeps a clean screen; Mo's tabs bring their own buttons.
            if !isGo, !isMo {
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
                selectedDate = day
                if detail != nil {
                    // The first tap already opened the event; swap it for a new event.
                    newEventAfterDetail = true
                    detail = nil
                } else {
                    openEditor(.new)
                }
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
        // The band also pages the day.
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .global)
                .onChanged(dragDay)
                .onEnded(endDayDrag)
        )
    }

    @ViewBuilder
    private func circleButton(_ icon: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        let label = Image(systemName: icon)
            .font(.system(size: prominent ? 26.4 : 24, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(width: 56, height: 56)
            .contentTransition(.symbolEffect(.replace))
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

    /// The undo toast sits between the bottom buttons (above the bar in ToDo) and leaves the screen usable.
    @ViewBuilder
    private var toastLayer: some View {
        // Mo shows the toast above its own tab bar.
        if let toast = toasts.current, !isMo {
            UndoToastView(toast: toast) { toasts.performUndo() }
                .padding(.horizontal, isTodo ? 20 : 20 + 56 + 10)
                .padding(.bottom, isTodo ? 20 + 56 + 12 : 20)
                .id(toast.id)
        }
    }

    /// While ＋ is held the screen dims and blurs little by little (still readable) and ＋ turns into ×;
    /// once held long enough Mo and Go pop up out of it. ＋ here is a copy drawn over the blur.
    @ViewBuilder
    private var fabMenuLayer: some View {
        let active = fabPress > 0 || fabMenuShown
        ZStack(alignment: .bottomTrailing) {
            if active {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.12))
                    .opacity(fabMenuShown ? 1 : fabPress)
                    .ignoresSafeArea()
            }
            VStack(alignment: .trailing, spacing: 26) {
                if fabMenuShown {
                    fabMenuRow(.go, name: "Go", logo: "GoLogo")
                        .transition(fabMenuTransition(delay: 0.05))
                    fabMenuRow(.mo, name: "Mo", logo: "MoLogo")
                        .transition(fabMenuTransition(delay: 0))
                }
                if active {
                    Button {} label: {
                        Image(systemName: "plus")
                            .font(.system(size: 26.4, weight: .semibold))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(45 * (fabMenuShown ? 1 : fabPress)))
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .scaleEffect(fabMenuShown && fabHover == nil && fabOverButton ? 1.06 : 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: fabHover)
                }
            }
            .padding(20)
        }
        .allowsHitTesting(false)
    }

    /// The finger is still on ＋ (or hasn't moved).
    private var fabOverButton: Bool {
        fabPoint.map { fabFrame.contains($0) } ?? true
    }

    /// Springs up out of ＋: grows from its corner and rises into place.
    private func fabMenuTransition(delay: Double) -> AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.2, anchor: .bottomTrailing)
                .combined(with: .offset(y: 36))
                .combined(with: .opacity)
                .animation(.spring(response: 0.38, dampingFraction: 0.68).delay(delay)),
            removal: .scale(scale: 0.4, anchor: .bottomTrailing)
                .combined(with: .offset(y: 24))
                .combined(with: .opacity)
                .animation(.easeIn(duration: 0.15))
        )
    }

    private func fabMenuRow(_ target: HomeMode, name: String, logo: String) -> some View {
        let hovered = fabHover == target
        return HStack(spacing: 14) {
            Text(name)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.primary)
            Image(logo)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .foregroundStyle(hovered ? Color.white : Color.brand)
                .frame(width: 52, height: 52)
                .background(Circle().fill(hovered ? Color.brand : Color.white))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                // Lines up with the middle of ＋ below.
                .padding(.trailing, 2)
        }
        .scaleEffect(hovered ? 1.1 : 1, anchor: .trailing)
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: hovered)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { fabMenuFrames[target] = $0 }
    }

    /// Which row the finger is on: its height, from a little left of its name to the screen's edge.
    private func fabMenuItem(at point: CGPoint) -> HomeMode? {
        fabMenuFrames.first { _, frame in
            point.y >= frame.minY - 7 && point.y <= frame.maxY + 7 && point.x >= frame.minX - 40
        }?.key
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

    /// On the already selected day a single tap opens the event right away; a double tap then swaps it for a new event.
    private func eventTapped(_ event: EKEvent, on day: Date) {
        guard CalendarMath.isSameDay(day, selectedDate) else {
            selectedDate = day
            return
        }
        openDetail(event)
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
        if url.host == "go" {
            mode = HomeMode.go.rawValue
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
        toasts.show("予定を削除しました") {
            do { try store.undoDelete() } catch { errorMessage = error.localizedDescription }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            store.clearLastDeleted(deleted.id)
        }
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
            do {
                let copies = try store.duplicate(event, to: current.targets.sorted())
                toasts.show("予定を複製しました") {
                    do {
                        for copy in copies { try store.delete(copy, recordUndo: false) }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        case .move:
            guard let day = current.targets.first else { return }
            let originalDay = CalendarMath.startOfDay(event.startDate)
            let run: (EKSpan) -> Void = { span in
                do {
                    try store.move(event, to: day, span: span)
                    toasts.show("予定を移動しました") {
                        do { try store.move(event, to: originalDay, span: span) } catch { errorMessage = error.localizedDescription }
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
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

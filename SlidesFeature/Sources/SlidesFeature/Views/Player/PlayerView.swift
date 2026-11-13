import SwiftUI

/// The steps of a slide's animations: what runs on entering the slide, then what each tap runs.
struct AnimationPlan {
    struct Timed {
        let animation: ElementAnimation
        /// Seconds after the step starts.
        let start: Double
    }

    /// Runs as the slide appears (animations before the first タップ時).
    var auto: [Timed] = []
    var taps: [[Timed]] = []

    init(_ slide: SlideContent) {
        let present = Set(slide.elements.map(\.id))
        var autoSteps: [Timed] = []
        var tapSteps: [[Timed]] = []
        var current: [Timed] = []
        var isAuto = true
        var previousStart = 0.0
        var previousEnd = 0.0
        for animation in slide.animations where present.contains(animation.elementID) {
            let start: Double
            switch animation.start {
            case .onTap:
                if isAuto { autoSteps = current } else if !current.isEmpty { tapSteps.append(current) }
                current = []
                isAuto = false
                start = animation.delay
            case .withPrevious:
                start = previousStart + animation.delay
            case .afterPrevious:
                start = previousEnd + animation.delay
            }
            current.append(Timed(animation: animation, start: start))
            previousStart = start
            previousEnd = max(previousEnd, start + animation.duration)
            if animation.start == .onTap { previousEnd = start + animation.duration }
        }
        if isAuto { autoSteps = current } else if !current.isEmpty { tapSteps.append(current) }
        auto = autoSteps
        taps = tapSteps
    }
}

/// How an element looks at a moment of playback.
struct ElementLook: Equatable {
    var visible: Bool
    /// How it comes in or goes out.
    var effect: AnimationEffect
    var category: AnimationCategory
}

/// 再生: full screen in landscape, one slide at a time on black.
/// Tap the right part (or swipe left) for next, the left part (or swipe right) for previous; a tap runs the next
/// animation step first. Tap the middle for the controls. Hold to edit this slide; swipe down to go back.
/// It opens on black, turns the screen, then fades the slide in (and the other way round when leaving),
/// so the turn happens out of sight.
struct PlayerView: View {
    let slides: [SlideContent]
    let deck: UUID
    var onExit: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index: Int
    @State private var step = 0
    @State private var looks: [UUID: ElementLook] = [:]
    @State private var forward = true
    /// The transition of the slide being shown next; set before the change, so the leaving slide uses it too.
    @State private var transitionKind = TransitionKind.none
    @State private var shown = false
    @State private var leaving = false
    @State private var showsControls = false
    @State private var hideControls: Task<Void, Never>?
    @State private var dragDown: CGFloat = 0
    /// Bumped on every slide change, so timers from the last slide stop.
    @State private var generation = 0

    init(slides: [SlideContent], deck: UUID, start: Int, onExit: @escaping (Int) -> Void) {
        self.slides = slides
        self.deck = deck
        self.onExit = onExit
        _index = State(initialValue: min(max(start, 0), max(slides.count - 1, 0)))
    }

    private var slide: SlideContent? { slides.indices.contains(index) ? slides[index] : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            stage
                .ignoresSafeArea()
                .opacity(shown ? 1 : 0)
            if showsControls, shown {
                controls
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            enter(animated: false, runAuto: false)
            SlidesOrientation.lock(.landscape, turnTo: .landscapeRight)
            // After the turn, behind black.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.3)) { shown = true }
                enter(animated: true)
            }
        }
        .sensoryFeedback(.selection, trigger: index)
    }

    private var stage: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / 1920, geo.size.height / 1080)
            ZStack {
                if let slide {
                    PlayedSlide(slide: slide, deck: deck, scale: scale, looks: looks)
                        .frame(width: 1920 * scale, height: 1080 * scale)
                        .id(slide.id)
                        .transition(transition(for: transitionKind))
                        .scaleEffect(1 - min(dragDown, 600) / 1400)
                        .offset(y: dragDown)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                tapped(at: location.x / max(geo.size.width, 1))
            }
            .onLongPressGesture(minimumDuration: 0.6) {
                exit()
            }
            .simultaneousGesture(drag)
        }
    }

    // MARK: Controls

    /// Inside the safe area (clear of the notch / Dynamic Island), small and translucent.
    private var controls: some View {
        ZStack {
            VStack {
                HStack {
                    controlButton("xmark", label: "閉じる") { exit() }
                    Spacer()
                }
                Spacer()
                Text("\(index + 1)/\(slides.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .glassEffect(.regular, in: .capsule)
            }
            HStack {
                controlButton("chevron.left", label: "前へ") { go(-1, animated: true) }
                    .disabled(index == 0)
                    .opacity(index == 0 ? 0.4 : 1)
                Spacer()
                controlButton("chevron.right", label: "次へ") { go(1, animated: true) }
                    .disabled(index >= slides.count - 1)
                    .opacity(index >= slides.count - 1 ? 0.4 : 1)
            }
        }
        .padding(12)
        .environment(\.colorScheme, .dark)
    }

    private func controlButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) { showsControls.toggle() }
        hideControls?.cancel()
        guard showsControls else { return }
        hideControls = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showsControls = false }
        }
    }

    // MARK: Gestures

    /// `fraction` is how far across the screen the tap was.
    private func tapped(at fraction: CGFloat) {
        guard shown else { return }
        if fraction > 0.38, fraction < 0.62 {
            toggleControls()
        } else if fraction >= 0.62 {
            advance()
        } else {
            go(-1, animated: true)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let dy = value.translation.height
                if dy > 0, dy > abs(value.translation.width) { dragDown = dy }
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if dragDown > 0 {
                    if dy > 160 {
                        exit()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dragDown = 0 }
                    }
                } else if abs(dx) > 50, abs(dx) > abs(dy) {
                    // A swipe skips the animations: the slide shows as it ends.
                    go(dx < 0 ? 1 : -1, animated: false)
                }
            }
    }

    /// Fades to black, turns back to portrait out of sight, then leaves.
    private func exit() {
        guard !leaving else { return }
        leaving = true
        let current = index
        withAnimation(.easeIn(duration: 0.2)) {
            shown = false
            showsControls = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            SlidesOrientation.lock(.portrait, turnTo: .portrait)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                onExit(current)
            }
        }
    }

    // MARK: Playing

    /// The next animation step, or the next slide when there's none left.
    private func advance() {
        guard let slide else { return }
        let plan = AnimationPlan(slide)
        if step < plan.taps.count {
            run(plan.taps[step])
            step += 1
        } else {
            go(1, animated: true)
        }
    }

    private func go(_ delta: Int, animated: Bool) {
        let target = index + delta
        guard slides.indices.contains(target), !leaving else { return }
        let kind = slides[target].transition.kind
        let duration = slides[target].transition.duration
        forward = delta > 0
        // The leaving slide takes its transition from what's drawn now, so set it before the change.
        transitionKind = kind
        DispatchQueue.main.async {
            if kind == .none {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { index = target }
            } else {
                withAnimation(.easeInOut(duration: duration)) { index = target }
            }
            enter(animated: animated)
        }
    }

    /// Sets up the slide's elements: with animations, as they start (then runs the automatic step);
    /// without, as they end.
    private func enter(animated: Bool, runAuto: Bool = true) {
        generation += 1
        step = 0
        guard let slide else { return }
        let plan = AnimationPlan(slide)
        var start: [UUID: ElementLook] = [:]
        var end: [UUID: ElementLook] = [:]
        for animation in slide.animations {
            let look = ElementLook(visible: animation.category == .exit, effect: animation.effect, category: animation.category)
            if start[animation.elementID] == nil { start[animation.elementID] = look }
            end[animation.elementID] = ElementLook(visible: animation.category == .entrance, effect: animation.effect, category: animation.category)
        }
        if animated {
            looks = start
            if runAuto { run(plan.auto) }
        } else {
            looks = end
            step = plan.taps.count
        }
    }

    private func run(_ timed: [AnimationPlan.Timed]) {
        let current = generation
        for item in timed {
            let animation = item.animation
            let look = ElementLook(visible: animation.category == .entrance, effect: animation.effect, category: animation.category)
            DispatchQueue.main.asyncAfter(deadline: .now() + item.start) {
                guard current == generation else { return }
                let curve: Animation? = animation.effect == .appear ? nil : .easeInOut(duration: animation.duration)
                withAnimation(curve) { looks[animation.elementID] = look }
            }
        }
    }

    private func transition(for kind: TransitionKind) -> AnyTransition {
        if reduceMotion { return kind == .none ? .identity : .opacity }
        switch kind {
        case .none:
            return .identity
        case .fade:
            return .opacity
        case .pushLeft:
            return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading), removal: .move(edge: forward ? .leading : .trailing))
        case .pushRight:
            return .asymmetric(insertion: .move(edge: forward ? .leading : .trailing), removal: .move(edge: forward ? .trailing : .leading))
        case .cover:
            // The new slide slides over the old one, which stays until covered.
            return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading), removal: .opacity.animation(.linear(duration: 0.01).delay(0.6)))
        case .zoom:
            return .asymmetric(insertion: .scale(scale: 0.3).combined(with: .opacity), removal: .opacity)
        }
    }
}

/// A slide as played: the background, and each element with its animation state.
struct PlayedSlide: View {
    let slide: SlideContent
    let deck: UUID
    let scale: CGFloat
    let looks: [UUID: ElementLook]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            SlideBackgroundView(background: slide.background, deck: deck)
                .frame(width: 1920 * scale, height: 1080 * scale)
            ForEach(slide.elements) { element in
                let frame = element.frame.cg
                let padding = SlideRenderer.padding
                let look = looks[element.id]
                ElementRenderView(element: element, deck: deck, scale: scale)
                    .frame(width: (frame.width + padding * 2) * scale, height: (frame.height + padding * 2) * scale)
                    .rotationEffect(.degrees(element.rotation))
                    .scaleEffect(hiddenScale(look))
                    .offset(hiddenOffset(look, frame: frame))
                    .opacity(element.opacity * hiddenOpacity(look))
                    .position(x: frame.midX * scale, y: frame.midY * scale)
            }
        }
        .frame(width: 1920 * scale, height: 1080 * scale, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
    }

    /// Slides stay opaque (they come from off the slide); everything else fades.
    private func hiddenOpacity(_ look: ElementLook?) -> Double {
        guard let look, !look.visible else { return 1 }
        switch look.effect {
        case .slideFromTop, .slideFromBottom, .slideFromLeft, .slideFromRight: return reduceMotion ? 0 : 1
        default: return 0
        }
    }

    private func hiddenScale(_ look: ElementLook?) -> CGFloat {
        guard let look, !look.visible, look.effect == .zoom, !reduceMotion else { return 1 }
        return 0.2
    }

    /// Off to its side while hidden, so it slides in from (or out to) there.
    private func hiddenOffset(_ look: ElementLook?, frame: CGRect) -> CGSize {
        guard let look, !look.visible, !reduceMotion else { return .zero }
        let distance = 1100 * scale
        switch look.effect {
        case .slideFromTop: return CGSize(width: 0, height: -distance)
        case .slideFromBottom: return CGSize(width: 0, height: distance)
        case .slideFromLeft: return CGSize(width: -distance * 1.6, height: 0)
        case .slideFromRight: return CGSize(width: distance * 1.6, height: 0)
        default: return .zero
        }
    }
}

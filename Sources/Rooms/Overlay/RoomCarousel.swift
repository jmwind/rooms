import AppKit
import QuartzCore
import RoomsCore

/// Your rooms, zoomed out, on a ring around you.
///
/// ⌥Space blurs the desk and lays the rooms out as miniatures of themselves: every
/// window where it will be, with a picture of it when Rooms has one. The room you're
/// on faces you; the ones either side are turned away on the surface of a large
/// sphere, so you always see a peek of what's next and what you just came from. The
/// ring has no end — keep going one way and you come back round.
///
/// Pressing Enter opens the middle card out to fill the screen, where the real
/// windows are about to land, so the miniature you chose becomes the room itself.
///
/// Drawn with layers rather than views: the cards are projected in 3D, and layers
/// sort by depth and hit-test through the projection without any help.
@MainActor
final class RoomCarousel {
    /// One window inside a room's miniature.
    struct Pane {
        /// Where it sits on the screen, 0…1 from the top-left of the usable area.
        let unit: CGRect
        let icon: NSImage?
        /// A picture of the window, when Rooms has one.
        let picture: NSImage?

        /// Whether it would draw the same thing: a picture arriving is a change.
        func draws(like other: Pane) -> Bool {
            unit == other.unit && picture === other.picture && icon === other.icon
        }
    }

    /// One room, as a card on the ring.
    struct Card {
        let id: String
        let name: String
        /// "Design · 4 windows".
        let detail: String
        /// "Current", "⌃⌥3", or both.
        let badge: String?
        /// Stands in for the miniature when the room has no windows saved yet.
        let icons: [NSImage]
        let panes: [Pane]

        /// Whether the card would draw the same thing, so the ring can turn without
        /// building its cards again.
        func draws(like other: Card) -> Bool {
            id == other.id && name == other.name && detail == other.detail && badge == other.badge
                && panes.count == other.panes.count
                && zip(panes, other.panes).allSatisfy { $0.draws(like: $1) }
        }
    }

    /// A card beside the middle one was clicked: turn the ring to it.
    var onTurn: (Int) -> Void = { _ in }
    /// The middle card was clicked, or the ring was flicked past it: walk in.
    var onChoose: () -> Void = {}
    /// The menu for the middle card (Edit Windows…, Delete Room).
    var menuForCard: () -> NSMenu? = { nil }
    /// A swipe or a wheel: one room on (+1) or back (-1).
    var onTurnBy: (Int) -> Void = { _ in }

    var isVisible: Bool { panel?.isVisible ?? false }

    private var panel: NSPanel?
    private var view: CarouselView?

    /// The ring fills the screen it opens on. The palette floats over it, which is
    /// where the rooms' names are.
    func show(_ cards: [Card], selected: Int) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
                ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let view = self.view ?? makeView(panel: panel)
        self.view = view

        let firstShow = !panel.isVisible
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: false) }
        view.stage = screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        view.set(cards, selected: selected, jump: firstShow)

        guard firstShow else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
                panel.animator().alphaValue = 1
            }
        }
    }

    /// Enter: the middle card opens out to where the real windows are about to land,
    /// and the ring stays as a veil over the desk until they have.
    func zoomIn() {
        guard isVisible else { return }
        view?.zoomIn()
    }

    func hide(animated: Bool = false, delay: TimeInterval = 0) {
        hideWork?.cancel()
        hideWork = nil
        guard let panel, panel.isVisible else { return }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            tearDown()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.12
                    panel.animator().alphaValue = 0
                }, completionHandler: { MainActor.assumeIsolated { self.tearDown() } })
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private var hideWork: DispatchWorkItem?

    private func tearDown() {
        hideWork?.cancel()
        hideWork = nil
        view?.stop()
        panel?.orderOut(nil)
        panel?.alphaValue = 1
    }

    // MARK: Building

    private func makePanel() -> NSPanel {
        let panel = RingPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                              backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        // Under the palette, which stays the thing you're typing into.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        return panel
    }

    private func makeView(panel: NSPanel) -> CarouselView {
        // The desk, blurred and dimmed, so the rooms are what you see.
        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        let view = CarouselView()
        view.autoresizingMask = [.width, .height]
        view.onTurn = { [weak self] i in self?.onTurn(i) }
        view.onChoose = { [weak self] in self?.onChoose() }
        view.menuForCard = { [weak self] in self?.menuForCard() ?? nil }
        view.onTurnBy = { [weak self] n in self?.onTurnBy(n) }
        blur.addSubview(view)
        panel.contentView = blur
        view.frame = blur.bounds
        return view
    }
}

/// The ring itself: holds a layer per card, turns them about the sphere on a spring,
/// and answers the mouse.
private final class CarouselView: NSView {
    var onTurn: (Int) -> Void = { _ in }
    var onChoose: () -> Void = {}
    var menuForCard: () -> NSMenu? = { nil }
    var onTurnBy: (Int) -> Void = { _ in }

    /// The screen's usable area, which every card is a zoom-out of and which the
    /// middle card opens out to fill.
    var stage: CGRect = .zero { didSet { if stage != oldValue { rebuild() } } }

    private var cards: [RoomCarousel.Card] = []
    private var instances: [(card: Int, turn: Int, layer: CardLayer)] = []
    private var card: CGSize = CGSize(width: 900, height: 560)
    private var centre: CGPoint = .zero
    /// The shape of the ring: see `Ring` in RoomsCore, which is where the awkward
    /// parts of this live and where they're tested.
    private var ring = Ring(count: 0)

    /// Where the ring is now and where it's heading, in cards. `settled` brings it
    /// back inside one lap each time it stops.
    private var scroll: CGFloat = 0
    private var target: CGFloat = 0
    private var velocity: CGFloat = 0
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var wheel: CGFloat = 0
    private var zoomed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { false }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rebuild()
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        rebuild()
    }

    // MARK: The cards

    func set(_ cards: [RoomCarousel.Card], selected: Int, jump: Bool) {
        let sameRooms = cards.map(\.id) == self.cards.map(\.id)
        let same = sameRooms && zip(cards, self.cards).allSatisfy { $0.draws(like: $1) }
        let wasZoomed = zoomed
        self.cards = cards
        ring = Ring(count: cards.count)
        zoomed = false
        // A new set, a layout Tab changed, a picture arrived, or a card is still
        // opened out from the room you last walked into.
        if !same || wasZoomed { rebuild() }
        guard !cards.isEmpty else { stop(); return }

        // Turn the short way round to the room that's now selected. Filtering as you
        // type puts different rooms on the ring, so there's nothing to turn through:
        // it already shows what you asked for.
        let leap = jump || !sameRooms
        let wanted = min(max(0, selected), cards.count - 1)
        if leap {
            scroll = CGFloat(wanted)
            target = scroll
            velocity = 0
            place()
            stop()
        } else {
            target = ring.target(wanted, scroll: scroll)
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                scroll = ring.settled(target)
                target = scroll
                velocity = 0
                place()
            } else {
                start()
            }
        }
    }

    private func rebuild() {
        instances.forEach { $0.layer.removeFromSuperlayer() }
        instances = []
        guard let layer, !cards.isEmpty, bounds.width > 200 else { return }

        // The room you're on is the point of the ring, so it's big: half the screen
        // across, in the shape of the screen, with the next and previous rooms
        // coming round the sphere behind it.
        let width = (bounds.width * 0.5).rounded()
        let shape = stage.width > 0 ? stage.height / stage.width : 0.62
        card = CGSize(width: width, height: (width * shape).rounded())
        // In the middle of the screen, a touch low: the palette floats over the top
        // of the ring, which is where the rooms' names are.
        centre = CGPoint(x: bounds.midX, y: bounds.midY - bounds.height * 0.04)

        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / (ring.eye * card.width)
        layer.sublayerTransform = perspective

        let scale = window?.backingScaleFactor ?? 2
        for (i, model) in cards.enumerated() {
            for turn in ring.turns(for: i) {
                let card = CardLayer(model: model, size: self.card, scale: scale)
                card.position = centre
                card.isHidden = true
                layer.addSublayer(card)
                instances.append((i, turn, card))
            }
        }
        place()
    }

    // MARK: Turning

    private func start() {
        guard link == nil else { return }
        lastTick = 0
        let link = displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
        // If the screen never asks us for a frame, the ring would sit there: land on
        // the room that was asked for rather than appear stuck.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.link != nil, self.lastTick == 0 else { return }
                Log.file("Ring: no frames from the display link; turning without it")
                self.scroll = self.ring.settled(self.target)
                self.target = self.scroll
                self.stop()
                self.place()
            }
        }
    }

    func stop() {
        link?.invalidate()
        link = nil
        velocity = 0
    }

    @objc private func tick(_ sender: CADisplayLink) {
        let now = sender.timestamp
        let dt = min(1.0 / 30, lastTick == 0 ? 1.0 / 60 : now - lastTick)
        lastTick = now

        // A quick spring: the ring should feel like it answered the key, not like it
        // has to catch up with you. Settles in about a fifth of a second.
        let stiffness: CGFloat = 460, damping: CGFloat = 34
        velocity += ((target - scroll) * stiffness - velocity * damping) * dt
        scroll += velocity * dt
        if abs(target - scroll) < 0.001, abs(velocity) < 0.02 {
            // Back inside one lap, so turning the same way for ever stays on the ring.
            scroll = ring.settled(target)
            target = scroll
            stop()
        }
        place()
    }

    /// Puts every card where the ring says it should be. Runs on every frame while
    /// the ring turns, so it allocates nothing and lays nothing out.
    private func place() {
        guard !cards.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for instance in instances {
            let away = ring.away(instance.card, scroll: scroll, turn: instance.turn)
            guard let spot = ring.spot(away: away) else {
                instance.layer.isHidden = true
                continue
            }
            let layer = instance.layer
            layer.isHidden = false
            var t = CATransform3DIdentity
            // On the surface of a large sphere: round to the side, away from you, and
            // lower the further round it goes.
            t = CATransform3DTranslate(t, spot.x * card.width, spot.y * card.width, spot.z * card.width)
            t = CATransform3DRotate(t, -spot.angle, 0, 1, 0)                   // facing the middle
            t = CATransform3DRotate(t, ring.tilt * abs(spot.angle), 1, 0, 0)   // lying on the sphere
            layer.transform = t
            layer.zPosition = -abs(spot.away)
            layer.opacity = Float(spot.presence)
            layer.setFocus(spot.presence, lit: max(0, 1 - abs(spot.away) * 2.5))
        }
        CATransaction.commit()
    }

    /// The card in the middle, and how far the ring is from resting on it.
    private var middle: (instance: Int, away: CGFloat)? {
        instances.indices
            .map { ($0, ring.away(instances[$0].card, scroll: scroll, turn: instances[$0].turn)) }
            .min { abs($0.1) < abs($1.1) }
            .map { (instance: $0.0, away: $0.1) }
    }

    // MARK: Opening out

    /// Enter: the middle card opens out to the size of the screen. The miniature is
    /// a true zoom-out of the desk, so every window lands exactly where the real one
    /// is about to. Snappy on purpose — the windows are already on their way.
    func zoomIn() {
        guard !zoomed, let middle, abs(middle.away) < 0.6 else { return }
        zoomed = true
        stop()
        let layer = instances[middle.instance].layer
        let opened = stage.width > 0 ? stage : bounds
        let scale = opened.width / card.width
        var t = CATransform3DMakeTranslation(opened.midX - centre.x, opened.midY - centre.y, 0)
        t = CATransform3DScale(t, scale, scale, 1)

        CATransaction.begin()
        CATransaction.setAnimationDuration(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.13)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.3, 0.9, 0.2, 1))
        layer.zPosition = 100
        layer.transform = t
        layer.opacity = 1
        layer.openOut()
        for other in instances where other.layer !== layer { other.layer.opacity = 0 }
        CATransaction.commit()
    }

    // MARK: Mouse

    override func mouseUp(with event: NSEvent) {
        guard let hit = cardIndex(at: event) else { return }
        if hit.middle { onChoose() } else { onTurn(hit.card) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let hit = cardIndex(at: event), hit.middle else { return nil }
        return menuForCard()
    }

    /// Two-finger swipes and the wheel turn the ring, a room at a time once you've
    /// pushed far enough that you meant it.
    override func scrollWheel(with event: NSEvent) {
        guard !zoomed else { return }
        let travel = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : -event.scrollingDeltaY
        wheel += travel
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 28 : 8
        while abs(wheel) >= threshold {
            onTurnBy(wheel > 0 ? -1 : 1)
            wheel -= wheel > 0 ? threshold : -threshold
        }
        if event.phase == .ended || event.momentumPhase == .ended { wheel = 0 }
    }

    /// Which card the pointer is over: layers hit-test through the projection, so
    /// this works on the cards that are turned away too.
    private func cardIndex(at event: NSEvent) -> (card: Int, middle: Bool)? {
        guard !zoomed, let layer, !cards.isEmpty else { return nil }
        var node = layer.hitTest(convert(event.locationInWindow, from: nil))
        while let current = node {
            if let i = instances.firstIndex(where: { $0.layer === current }) {
                return (instances[i].card, abs(ring.away(instances[i].card, scroll: scroll, turn: instances[i].turn)) < 0.5)
            }
            node = current.superlayer
        }
        return nil
    }
}

/// One room's card: the screen, zoomed out, with a pane for each window. The room's
/// name isn't here — it's in the palette, which floats over the ring.
private final class CardLayer: CALayer {
    private let dim = CALayer()

    init(model: RoomCarousel.Card, size: CGSize, scale: CGFloat) {
        super.init()
        frame = CGRect(origin: .zero, size: size)
        contentsScale = scale
        cornerRadius = 20
        cornerCurve = .continuous
        backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        borderWidth = 1
        borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        shadowColor = NSColor.black.cgColor
        shadowOpacity = 0.55
        shadowRadius = 34
        shadowOffset = CGSize(width: 0, height: -12)

        // The windows. Drawn back to front, so the room's first window ends up on
        // top — which is what you see for real, and what matters in a Stack.
        let field = bounds.insetBy(dx: 12, dy: 12)
        for pane in model.panes.reversed() {
            let unit = pane.unit
            let rect = CGRect(x: field.minX + unit.minX * field.width,
                              // The units come from the screen, where y runs down.
                              y: field.minY + (1 - unit.maxY) * field.height,
                              width: max(8, unit.width * field.width),
                              height: max(8, unit.height * field.height))
            let window = CALayer()
            window.frame = rect.insetBy(dx: 2, dy: 2)
            window.cornerRadius = min(10, min(rect.width, rect.height) / 5)
            window.cornerCurve = .continuous
            window.masksToBounds = true
            window.borderWidth = 1
            window.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
            window.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
            window.contentsScale = scale
            if let picture = pane.picture, let image = Self.cgImage(picture) {
                window.contents = image
                window.contentsGravity = .resizeAspectFill
            } else if let icon = pane.icon, let image = Self.cgImage(icon) {
                let side = min(window.bounds.width, window.bounds.height) * 0.4
                let glyph = CALayer()
                glyph.frame = CGRect(x: (window.bounds.width - side) / 2, y: (window.bounds.height - side) / 2,
                                     width: side, height: side)
                glyph.contents = image
                glyph.contentsGravity = .resizeAspect
                glyph.contentsScale = scale
                window.addSublayer(glyph)
            }
            addSublayer(window)
        }

        // A room with nothing saved in it yet: its apps' icons, in a row.
        if model.panes.isEmpty {
            let side = min(72, size.width / 9), gap = side / 3
            let icons = Array(model.icons.prefix(5))
            let total = CGFloat(icons.count) * side + CGFloat(max(0, icons.count - 1)) * gap
            for (i, icon) in icons.enumerated() {
                guard let image = Self.cgImage(icon) else { continue }
                let glyph = CALayer()
                glyph.frame = CGRect(x: bounds.midX - total / 2 + CGFloat(i) * (side + gap),
                                     y: bounds.midY - side / 2, width: side, height: side)
                glyph.contents = image
                glyph.contentsGravity = .resizeAspect
                glyph.contentsScale = scale
                addSublayer(glyph)
            }
        }

        // Everything but the card you're on is pushed back into the dark.
        dim.frame = bounds
        dim.cornerRadius = cornerRadius
        dim.cornerCurve = .continuous
        dim.backgroundColor = NSColor.black.cgColor
        dim.opacity = 0
        addSublayer(dim)
    }

    required init?(coder: NSCoder) { fatalError("not used") }
    override init(layer: Any) { super.init(layer: layer) }

    /// `focus` falls away across the ring and `lit` only the middle card has: the
    /// room you're on is bright and wears the accent edge, and the ones either side
    /// are turned down without going dark.
    func setFocus(_ focus: CGFloat, lit: CGFloat) {
        dim.opacity = Float((1 - focus) * 0.45)
        borderColor = lit > 0
            ? NSColor.controlAccentColor.withAlphaComponent(0.3 + lit * 0.6).cgColor
            : NSColor.white.withAlphaComponent(0.16).cgColor
        borderWidth = 1 + lit * 2
        shadowOpacity = Float(0.35 + focus * 0.3)
    }

    /// Opening out to fill the screen: it stops being a card.
    func openOut() {
        dim.opacity = 0
        borderWidth = 0
        shadowOpacity = 0
        cornerRadius = 0
    }

    private static func cgImage(_ image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

/// Takes the mouse without ever taking the keyboard: the palette stays the window
/// you're typing into, so clicking a card doesn't close the thing that owns it.
private final class RingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

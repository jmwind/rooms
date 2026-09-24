import AppKit
import QuartzCore

/// Shows where a room's windows will go before anything moves. The desk behind
/// blurs (like Mission Control) and each window appears as a solid mini-window:
/// a title bar with the app and window name, and the app's icon. When the layout
/// changes (Tab in the palette), the same cards glide to their new places.
/// Click-through, one borderless window per display, drawn below the palette.
@MainActor
final class LayoutPreview {
    struct Card {
        let id: String        // the same window keeps the same card, so it can glide
        let rect: CGRect      // AX coordinates
        let icon: NSImage?
        let title: String
        let subtitle: String
    }

    private var windows: [NSWindow] = []
    private var layers: [NSView] = []                 // the card container in each window
    private var cardViews: [[String: CardView]] = []  // per display, by card id
    private var highlights: [HighlightView?] = []     // the lit separator, per display

    /// `cards` in back-to-front order. `avoiding`: the palette's frame (Cocoa screen
    /// coordinates), which card labels stay clear of.
    func show(_ cards: [Card], avoiding: CGRect? = nil) {
        rebuildWindowsIfNeeded()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        for (s, (screen, window)) in zip(NSScreen.screens, windows).enumerated() {
            let container = layers[s]
            var existing = cardViews[s]
            var seen = Set<String>()
            let firstShow = !window.isVisible

            for card in cards {
                // AX (top-left origin) → this screen's local Cocoa coordinates.
                let global = CGRect(x: card.rect.minX, y: primaryHeight - card.rect.maxY, width: card.rect.width, height: card.rect.height)
                guard global.intersects(screen.frame) else { continue }
                let local = global.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
                let clear = avoiding.map { $0.offsetBy(dx: -global.minX, dy: -global.minY) }
                seen.insert(card.id)

                if let view = existing[card.id], !firstShow {
                    // Same window, new place: glide there.
                    container.addSubview(view, positioned: .above, relativeTo: nil) // keep front-to-back order
                    if reduceMotion {
                        view.frame = local
                        view.fit(avoiding: clear)
                    } else {
                        NSAnimationContext.runAnimationGroup { ctx in
                            ctx.duration = 0.32
                            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
                            ctx.allowsImplicitAnimation = true
                            view.animator().frame = local
                            view.fit(avoiding: clear)
                            view.layoutSubtreeIfNeeded()
                        }
                    }
                } else {
                    existing[card.id]?.removeFromSuperview()
                    let view = CardView(card: card, frame: local)
                    view.fit(avoiding: clear)
                    container.addSubview(view)
                    existing[card.id] = view
                    if !reduceMotion {
                        view.alphaValue = 0
                        NSAnimationContext.runAnimationGroup { ctx in
                            ctx.duration = 0.2
                            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
                            view.animator().alphaValue = 1
                        }
                    }
                }
            }

            // Cards for windows that aren't in this layout any more fade away.
            for (id, view) in existing where !seen.contains(id) {
                existing[id] = nil
                if reduceMotion || firstShow {
                    view.removeFromSuperview()
                } else {
                    NSAnimationContext.runAnimationGroup({ ctx in
                        ctx.duration = 0.18
                        view.animator().alphaValue = 0
                    }, completionHandler: { MainActor.assumeIsolated { view.removeFromSuperview() } })
                }
            }
            cardViews[s] = existing
            // The lit separator stays over the cards.
            if let bar = highlights[s] { container.addSubview(bar, positioned: .above, relativeTo: nil) }

            if firstShow {
                window.alphaValue = reduceMotion ? 1 : 0
                window.orderFrontRegardless()
                if !reduceMotion {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.2
                        window.animator().alphaValue = 1
                    }
                }
            }
        }
    }

    /// Lights up the separator between windows that the arrow keys move (manual resize
    /// mode): `rect` is the gap between them in AX coordinates; nil puts the light out.
    func highlight(_ rect: CGRect?) {
        guard !windows.isEmpty else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (s, (screen, window)) in zip(NSScreen.screens, windows).enumerated() {
            var bar: CGRect?
            if let rect, !rect.isNull, rect.width > 0, rect.height > 0, window.isVisible {
                let global = CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
                if global.intersects(screen.frame) {
                    let local = global.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
                    // A little wider than the gap, so it reads over the cards' borders.
                    let vertical = local.height > local.width
                    bar = local.insetBy(dx: vertical ? -4 : 0, dy: vertical ? 0 : -4)
                }
            }
            guard let bar else {
                highlights[s]?.removeFromSuperview()
                highlights[s] = nil
                continue
            }
            if let view = highlights[s] {
                layers[s].addSubview(view, positioned: .above, relativeTo: nil)
                if reduceMotion {
                    view.frame = bar
                } else {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.32
                        ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
                        view.animator().frame = bar
                    }
                }
            } else {
                let view = HighlightView(frame: bar)
                layers[s].addSubview(view, positioned: .above, relativeTo: nil)
                highlights[s] = view
                if !reduceMotion {
                    view.alphaValue = 0
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.2
                        view.animator().alphaValue = 1
                    }
                }
            }
        }
    }

    /// Fades out; used after Enter so the windows settle under a soft veil.
    func hide(animated: Bool = false, delay: TimeInterval = 0) {
        guard windows.contains(where: \.isVisible) else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated, !reduceMotion else { tearDown(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, windows] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
                windows.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: { MainActor.assumeIsolated { self?.tearDown() } })
        }
    }

    private func tearDown() {
        windows.forEach { $0.orderOut(nil) }
        for s in cardViews.indices {
            cardViews[s].values.forEach { $0.removeFromSuperview() }
            cardViews[s] = [:]
        }
        for s in highlights.indices {
            highlights[s]?.removeFromSuperview()
            highlights[s] = nil
        }
    }

    private func rebuildWindowsIfNeeded() {
        let frames = NSScreen.screens.map(\.frame)
        if windows.map(\.frame) == frames { return }
        windows.forEach { $0.orderOut(nil) }
        layers = []
        cardViews = Array(repeating: [:], count: frames.count)
        highlights = Array(repeating: nil, count: frames.count)
        windows = frames.map { frame in
            let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle, .stationary]
            w.animationBehavior = .none
            w.setFrame(frame, display: false)

            let size = NSRect(origin: .zero, size: frame.size)
            // The desk, blurred and slightly darkened, so only the new layout reads.
            let blur = NSVisualEffectView(frame: size)
            blur.material = .fullScreenUI
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.autoresizingMask = [.width, .height]
            let tint = NSView(frame: size)
            tint.wantsLayer = true
            tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
            tint.autoresizingMask = [.width, .height]
            let container = NSView(frame: size)
            container.autoresizingMask = [.width, .height]
            blur.addSubview(tint)
            blur.addSubview(container)
            w.contentView = blur
            layers.append(container)
            return w
        }
    }
}

/// The separator being moved: a pill of light along the gap between its windows.
private final class HighlightView: NSView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = min(frame.width, frame.height) / 2
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 2
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 14
        layer?.shadowOffset = .zero
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
            layer?.shadowColor = NSColor.controlAccentColor.cgColor
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

/// One window-to-be, drawn as a simplified window.
private final class CardView: NSView {
    private let icon: NSImageView
    private var iconCenterY: NSLayoutConstraint!
    private var iconWidth: NSLayoutConstraint!
    private var iconHeight: NSLayoutConstraint!
    private let hasIcon: Bool

    init(card: LayoutPreview.Card, frame: CGRect) {
        icon = NSImageView(image: card.icon ?? NSImage())
        hasIcon = card.icon != nil
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 2
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 24
        layer?.shadowOffset = CGSize(width: 0, height: -8)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.shadowColor = NSColor.black.withAlphaComponent(0.25).cgColor
        }

        // Title bar: three quiet dots, the app, and the window's title.
        let dots = NSStackView(views: (0..<3).map { _ in
            let d = NSView()
            d.wantsLayer = true
            d.layer?.cornerRadius = 4
            d.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
            d.translatesAutoresizingMaskIntoConstraints = false
            d.widthAnchor.constraint(equalToConstant: 8).isActive = true
            d.heightAnchor.constraint(equalToConstant: 8).isActive = true
            return d
        })
        dots.spacing = 8
        let app = NSTextField(labelWithString: card.title)
        app.font = .systemFont(ofSize: 13, weight: .semibold)
        app.textColor = .labelColor
        app.setContentCompressionResistancePriority(.required, for: .horizontal)
        let windowTitle = NSTextField(labelWithString: card.subtitle.isEmpty ? "" : "—  \(card.subtitle)")
        windowTitle.font = .systemFont(ofSize: 13)
        windowTitle.textColor = .secondaryLabelColor
        windowTitle.lineBreakMode = .byTruncatingTail
        windowTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        for label in [app, windowTitle] { label.setContentHuggingPriority(.defaultHigh, for: .horizontal) }
        let titleBar = NSStackView(views: [dots, app, windowTitle, spacer])
        titleBar.spacing = 12
        titleBar.alignment = .centerY
        titleBar.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        let rule = NSBox()
        rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleBar)
        addSubview(rule)

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        iconWidth = icon.widthAnchor.constraint(equalToConstant: 64)
        iconHeight = icon.heightAnchor.constraint(equalToConstant: 64)
        iconCenterY = icon.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -frame.height / 2)
        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: 40),
            rule.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            iconWidth, iconHeight,
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconCenterY,
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Sizes and places the icon for the card's current frame: large on big cards,
    /// hidden on slivers, and out from under the palette.
    func fit(avoiding: CGRect?) {
        let f = frame
        let side: CGFloat = f.height > 320 && f.width > 320 ? 96 : 64
        iconWidth.constant = side
        iconHeight.constant = side
        icon.isHidden = !hasIcon || f.height < 160
        iconCenterY.constant = -centerFromBottom(size: f.size, avoiding: avoiding, side: side)
    }

    /// Middle of the body, or of the largest part the palette doesn't cover when the
    /// palette sits over the icon's column.
    private func centerFromBottom(size: CGSize, avoiding: CGRect?, side: CGFloat) -> CGFloat {
        var lo: CGFloat = 0, hi = size.height - 40   // below the title bar (Cocoa: y up)
        let column = (size.width - side) / 2 ... (size.width + side) / 2
        if let a = avoiding, a.maxY > lo, a.minY < hi, a.maxX > column.lowerBound, a.minX < column.upperBound {
            let below = (lo, max(lo, a.minY)), above = (min(hi, a.maxY), hi)
            (lo, hi) = (below.1 - below.0) >= (above.1 - above.0) ? below : above
        }
        return (lo + hi) / 2
    }
}

import AppKit

/// The first thing a new user sees: what Rooms is and the three steps to a first
/// room. Shown on launch until a room exists; also available from Getting Started.
@MainActor
final class Welcome: NSObject {
    private var panel: NSPanel?
    private let width: CGFloat = 480

    /// `shortcut`: the palette key as shown ("⌥ Space"). `needsAccess`: Accessibility
    /// isn't allowed yet, so the main button asks for it first.
    func show(shortcut: String, needsAccess: Bool, onAllow: @escaping () -> Void) {
        self.onAllow = onAllow
        let panel = makePanel(shortcut: shortcut, needsAccess: needsAccess)
        self.panel?.orderOut(nil)
        self.panel = panel

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let size = panel.contentView?.fittingSize ?? NSSize(width: width, height: 400)
        let v = screen.visibleFrame
        panel.setFrame(NSRect(x: v.midX - size.width / 2, y: v.midY - size.height / 2 + v.height * 0.1, width: size.width, height: size.height), display: true)

        // No fade: at launch the app isn't active yet, and a panel that starts
        // transparent can stay that way.
        panel.alphaValue = 1
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private var onAllow: () -> Void = {}

    @objc private func startClicked() { panel?.orderOut(nil) }

    @objc private func allowClicked() {
        onAllow()
        panel?.orderOut(nil)
    }

    // MARK: Building

    private func makePanel(shortcut: String, needsAccess: Bool) -> NSPanel {
        let panel = WelcomePanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 400),
                                 styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        // Panels hide whenever their app isn't active, and at launch Finder still is.
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.onCancel = { [weak self] in self?.startClicked() }

        let title = label("Welcome to Rooms", size: 24, weight: .semibold, color: .labelColor)
        let intro = label("A room is a set of windows for one project. Walk into a room and its windows come back, laid out neatly. Everything else hides, and nothing is ever closed.",
                          size: 14, weight: .regular, color: .secondaryLabelColor)

        let steps = NSStackView(views: [
            step(1, "Open the windows for one project."),
            step(2, "Press \(shortcut), type a name for the room, and press Enter."),
            step(3, "Click the windows that belong in it, then Create Room."),
            step(4, "To change the layout, press \(shortcut), select the room and press Tab."),
        ])
        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 16

        let after = label("From then on, \(shortcut) and the room's name brings it back. Rooms lives in the menu bar.",
                          size: 14, weight: .regular, color: .secondaryLabelColor)

        var views: [NSView] = [title, intro, steps, after]
        if needsAccess {
            views.append(label("Rooms needs Accessibility access to move windows. Nothing leaves your Mac.",
                               size: 14, weight: .semibold, color: .labelColor))
        }

        let primary = NSButton(title: needsAccess ? "Allow Accessibility…" : "Get Started", target: self,
                               action: needsAccess ? #selector(allowClicked) : #selector(startClicked))
        primary.bezelStyle = .push
        primary.controlSize = .large
        primary.bezelColor = .controlAccentColor
        primary.keyEquivalent = "\r"
        var buttons: [NSView] = [NSView()]
        if needsAccess {
            let later = NSButton(title: "Later", target: self, action: #selector(startClicked))
            later.bezelStyle = .push
            later.controlSize = .large
            buttons.append(later)
        }
        buttons.append(primary)
        let actions = NSStackView(views: buttons)
        actions.spacing = 8
        views.append(actions)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.setCustomSpacing(8, after: title)
        stack.setCustomSpacing(24, after: intro)
        stack.setCustomSpacing(24, after: steps)
        stack.setCustomSpacing(24, after: views[views.count - 2])
        stack.edgeInsets = NSEdgeInsets(top: 32, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for v in views {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        }
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true

        // Same surface as the palette: glass on macOS 26, a matching material before.
        // Tinted like the toast so the steps read clearly over busy windows.
        if let glass = Glass.surface(stack, tint: NSColor.windowBackgroundColor.withAlphaComponent(0.85)) {
            panel.contentView = glass
            // Glass draws its own edge; the window's rectangular shadow would show as a
            // square border behind the rounded corners.
            panel.hasShadow = false
        } else {
            let material = NSVisualEffectView()
            material.material = .popover
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = 24
            material.layer?.masksToBounds = true
            material.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: material.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: material.trailingAnchor),
                stack.topAnchor.constraint(equalTo: material.topAnchor),
                stack.bottomAnchor.constraint(equalTo: material.bottomAnchor),
            ])
            panel.contentView = material
            panel.hasShadow = true   // follows the rounded material, so no square edge
        }
        return panel
    }

    private func step(_ n: Int, _ text: String) -> NSView {
        let number = label("\(n)", size: 14, weight: .semibold, color: .controlAccentColor)
        number.alignment = .center
        number.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let body = label(text, size: 14, weight: .regular, color: .labelColor)
        let row = NSStackView(views: [number, body])
        row.alignment = .firstBaseline
        row.spacing = 8
        return row
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.isSelectable = false
        return field
    }
}

/// Closes on Esc, like the palette.
private final class WelcomePanel: NSPanel {
    var onCancel: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel() }
}

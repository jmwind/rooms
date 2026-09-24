import AppKit

/// "Which windows belong in this room?" Every open window appears as a card, the way
/// Mission Control shows them. Click to add (or Tab to a card and press Space); the
/// number on a card is its place in the room, and 1 is the main window. Name the
/// room, press Enter.
@MainActor
final class RoomPicker: NSObject, NSTextFieldDelegate {
    struct Choice {
        let name: String
        /// The room's name when the picker opened; empty for a new room. Differs
        /// from `name` when you rename it.
        let originalName: String
        let about: String
        let windows: [LiveWindow]
        /// Which opening of the picker this came from (see `finishSaving`).
        let session: Int
    }

    /// Create or Save was pressed. The picker stays up (covering the desk) until the
    /// app calls `hide()`.
    var onDone: (Choice) -> Void = { _ in }
    /// "Delete Room" was confirmed (edit mode only).
    var onDelete: (String) -> Void = { _ in }
    private let deleteButton = NSButton(title: "Delete Room", target: nil, action: nil)
    private var deleteArmed = false
    private var editingName = ""
    /// The name stopped changing (half a second after typing).
    var onNameSettled: (String) -> Void = { _ in }
    private var nameWork: DispatchWorkItem?
    var isVisible: Bool { panel?.isVisible ?? false }

    private var panel: PickerPanel?
    private var windows: [LiveWindow] = []
    private var order: [Int] = []          // selected window indices, in room order
    private var cards: [PickerCard] = []
    private let nameField = NSTextField()
    private let aboutField = NSTextField()
    /// What you've written about the room ("the deck, its research tabs, the notes").
    var about: String { aboutField.stringValue.trimmingCharacters(in: .whitespaces) }

    /// Fills in what the room is about (from a template) unless you've written something.
    func suggestAbout(_ text: String) {
        if about.isEmpty { aboutField.stringValue = text }
    }
    private let heading = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private var userTouched = false
    private let createButton = NSButton(title: "Create Room", target: nil, action: nil)
    private let grid = FlippedView()
    private let scroll = NSScrollView()
    private var columns = 1
    private var icons: [String: NSImage] = [:]

    /// `preselected`: indices into `windows`, in room order.
    func show(windows: [LiveWindow], name: String, about: String = "", preselected: [Int], editing: Bool) {
        self.windows = windows
        order = preselected
        saving = false
        session += 1
        userTouched = false
        let panel = self.panel ?? makePanel()
        self.panel = panel

        heading.stringValue = editing ? "Edit Room" : "New Room"
        editingName = editing ? name : ""
        deleteArmed = false
        deleteButton.title = "Delete Room"
        deleteButton.bezelColor = nil
        deleteButton.isHidden = !editing
        createButton.title = editing ? "Save Room" : "Create Room"
        nameField.stringValue = name
        aboutField.stringValue = about

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        panel.setFrame(screen.frame, display: false)
        buildCards()
        refresh()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nameField)
        nameField.currentEditor()?.selectAll(nil)
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: Building

    private func makePanel() -> PickerPanel {
        let panel = PickerPanel()
        panel.onSelectAll = { [weak self] in self?.selectAll() }
        panel.onCancel = { [weak self] in if self?.saving == false { self?.hide() } }
        panel.autorecalculatesKeyViewLoop = false   // Tab order is set by hand (see buildCards)

        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        tint.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(tint)

        // Header: what you're making, its name, how many windows, and the actions.
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        nameField.font = .systemFont(ofSize: 28)
        nameField.placeholderString = "Room name"
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.delegate = self
        nameField.cell?.usesSingleLineMode = true
        nameField.cell?.isScrollable = true
        nameField.setAccessibilityLabel("Room name")
        aboutField.font = .systemFont(ofSize: 14)
        aboutField.placeholderString = "What's in this room? e.g. the deck, its research tabs, the notes"
        aboutField.isBordered = false
        aboutField.drawsBackground = false
        aboutField.focusRingType = .none
        aboutField.textColor = .secondaryLabelColor
        aboutField.delegate = self
        aboutField.cell?.usesSingleLineMode = true
        aboutField.cell?.isScrollable = true
        aboutField.setAccessibilityLabel("What's in this room")
        countLabel.font = .systemFont(ofSize: 13)
        countLabel.textColor = .secondaryLabelColor
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancel.bezelStyle = .push
        cancel.controlSize = .large
        createButton.target = self
        createButton.action = #selector(createClicked)
        createButton.bezelStyle = .push
        createButton.controlSize = .large
        createButton.bezelColor = .controlAccentColor
        createButton.hasDestructiveAction = false
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        deleteButton.bezelStyle = .push
        deleteButton.controlSize = .large
        let actions = NSStackView(views: [countLabel, NSView(), deleteButton, cancel, createButton])
        actions.spacing = 8
        actions.alignment = .centerY
        let rule = NSBox()
        rule.boxType = .separator
        let headerStack = NSStackView(views: [heading, nameField, aboutField, rule, actions])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 12
        headerStack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        for v in [nameField, aboutField, rule, actions] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: headerStack.widthAnchor, constant: -48).isActive = true
        }

        let header: NSView
        if let glass = Glass.surface(headerStack) {
            header = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .popover
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = 24
            material.layer?.masksToBounds = true
            headerStack.translatesAutoresizingMaskIntoConstraints = false
            material.addSubview(headerStack)
            NSLayoutConstraint.activate([
                headerStack.leadingAnchor.constraint(equalTo: material.leadingAnchor),
                headerStack.trailingAnchor.constraint(equalTo: material.trailingAnchor),
                headerStack.topAnchor.constraint(equalTo: material.topAnchor),
                headerStack.bottomAnchor.constraint(equalTo: material.bottomAnchor),
            ])
            header = material
        }
        header.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "Click the windows that belong in this room, or Tab to one and press Space. 1 is the main window.   ⌘A Select all   ↵ Create   esc Cancel")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = NSColor.white.withAlphaComponent(0.85)
        hint.translatesAutoresizingMaskIntoConstraints = false

        scroll.documentView = grid
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        for v in [header, hint, scroll] { blur.addSubview(v) }
        NSLayoutConstraint.activate([
            tint.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            tint.topAnchor.constraint(equalTo: blur.topAnchor),
            tint.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            header.topAnchor.constraint(equalTo: blur.safeAreaLayoutGuide.topAnchor, constant: 48),
            header.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
            header.widthAnchor.constraint(equalToConstant: 640),
            hint.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            hint.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
            scroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 24),
            scroll.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 48),
            scroll.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -48),
            scroll.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -48),
        ])
        panel.contentView = blur
        return panel
    }

    private func buildCards() {
        grid.subviews.forEach { $0.removeFromSuperview() }
        cards = windows.enumerated().map { i, win in
            let card = PickerCard(
                icon: icon(win.bundleID),
                app: win.app.localizedName ?? win.bundleID,
                title: win.title,
                note: win.app.isHidden ? "Hidden" : (win.isMinimized ? "Minimized" : nil)
            )
            card.onClick = { [weak self] in self?.toggle(i) }
            card.onCreate = { [weak self] in self?.create() }
            card.onMove = { [weak self] dx, dy in self?.moveFocus(from: i, dx, dy) }
            grid.addSubview(card)
            return card
        }
        // Tab goes from the name and the description to the cards in reading order,
        // then round to the name again.
        nameField.nextKeyView = aboutField
        var previous: NSView = aboutField
        for card in cards {
            previous.nextKeyView = card
            previous = card
        }
        previous.nextKeyView = nameField
        layoutGrid()
    }

    /// Arrow keys on a focused card: the card beside it, or the one above or below.
    private func moveFocus(from i: Int, _ dx: Int, _ dy: Int) {
        let j = i + dx + dy * columns
        guard cards.indices.contains(j), dx == 0 || i / columns == j / columns else { NSSound.beep(); return }
        panel?.makeFirstResponder(cards[j])
    }

    private func layoutGrid() {
        let size = CGSize(width: 240, height: 168), gap: CGFloat = 16
        let available = max(size.width, (panel?.frame.width ?? 1200) - 96)
        columns = max(1, Int((available + gap) / (size.width + gap)))
        let used = CGFloat(columns) * size.width + CGFloat(columns - 1) * gap
        let inset = max(0, (available - used) / 2)
        for (i, card) in cards.enumerated() {
            let row = i / columns, col = i % columns
            card.frame = CGRect(x: inset + CGFloat(col) * (size.width + gap), y: CGFloat(row) * (size.height + gap), width: size.width, height: size.height)
        }
        let rows = (cards.count + columns - 1) / columns
        grid.frame = CGRect(x: 0, y: 0, width: available, height: max(0, CGFloat(rows) * (size.height + gap) - gap))
    }

    // MARK: Selecting

    private func toggle(_ i: Int) {
        userTouched = true
        if let k = order.firstIndex(of: i) { order.remove(at: k) } else { order.append(i) }
        refresh()
    }

    private func selectAll() {
        userTouched = true
        for i in windows.indices where !order.contains(i) { order.append(i) }
        refresh()
    }

    private func refresh() {
        for (i, card) in cards.enumerated() {
            card.position = order.firstIndex(of: i).map { $0 + 1 }
        }
        let n = order.count
        countLabel.stringValue = n == 0 ? "No windows selected" : (n == 1 ? "1 window" : "\(n) windows")
        createButton.isEnabled = n > 0 && !nameField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: Actions

    @objc private func createClicked() { create() }
    // Once Create is pressed the save is under way (the app closes the picker when
    // it's done): Cancel, Esc and Delete no longer apply.
    @objc private func cancelClicked() { if !saving { hide() } }

    /// First click arms it (red), second click deletes. Windows are never closed.
    @objc private func deleteClicked() {
        guard !editingName.isEmpty, !saving else { return }
        if deleteArmed {
            hide()
            onDelete(editingName)
        } else {
            deleteArmed = true
            deleteButton.title = "Click Again to Delete"
            deleteButton.bezelColor = .systemRed
        }
    }

    /// Set once Create is pressed, so a second press while the app measures the
    /// windows doesn't save the room twice.
    private var saving = false
    private var session = 0

    /// Closes the picker once its save has measured the windows behind it, unless it
    /// has since been reopened for something else.
    func finishSaving(_ session: Int) {
        guard session == self.session, saving else { return }
        saving = false
        hide()
    }

    private func create() {
        guard !saving else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !order.isEmpty else { NSSound.beep(); return }
        saving = true
        let chosen = order.map { windows[$0] }
        // The app hides the picker once it has measured the windows behind it.
        onDone(Choice(name: name, originalName: editingName, about: about, windows: chosen, session: session))
    }

    func controlTextDidChange(_ obj: Notification) {
        refresh()
        nameWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, isVisible else { return }
            onNameSettled(nameField.stringValue.trimmingCharacters(in: .whitespaces))
        }
        nameWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): create(); return true
        case #selector(NSResponder.cancelOperation(_:)): if !saving { hide() }; return true
        default: return false
        }
    }

    private func icon(_ bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 48, height: 48)
        icons[bundleID] = image
        return image
    }
}

/// Full-screen, takes keystrokes without activating Rooms.
private final class PickerPanel: NSPanel {
    var onSelectAll: () -> Void = {}
    var onCancel: () -> Void = {}

    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
    }

    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "a",
           !(firstResponder is NSTextView && !((firstResponder as? NSTextView)?.string.isEmpty ?? true)) {
            onSelectAll()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { onCancel() }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// One window: app icon, app name, window title. Selected cards carry their number.
/// Cards take keyboard focus: Space toggles, the arrows move to a neighbour, Enter creates.
private final class PickerCard: NSView {
    var onClick: () -> Void = {}
    var onCreate: () -> Void = {}
    /// Focus moves by columns and rows (left, right, up, down).
    var onMove: (Int, Int) -> Void = { _, _ in }
    var position: Int? { didSet { applyState() } }
    private let noteLabel = NSTextField(labelWithString: "")
    private var baseNote: String?

    private let badge = NSTextField(labelWithString: "")
    private let badgeBack = NSView()

    init(icon: NSImage?, app: String, title: String, note: String?) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 16
        focusRingType = .exterior
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(app), \(title)")

        let iconView = NSImageView(image: icon ?? NSImage())
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 48).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let appLabel = NSTextField(labelWithString: app)
        appLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        appLabel.lineBreakMode = .byTruncatingTail
        let titleLabel = NSTextField(wrappingLabelWithString: title.isEmpty ? " " : title)
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .center
        baseNote = note
        noteLabel.font = .systemFont(ofSize: 12)
        noteLabel.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [iconView, appLabel, titleLabel, noteLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.setCustomSpacing(12, after: iconView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        badgeBack.wantsLayer = true
        badgeBack.layer?.cornerRadius = 14
        badgeBack.translatesAutoresizingMaskIntoConstraints = false
        badge.font = .systemFont(ofSize: 13, weight: .semibold)
        badge.textColor = .white
        badge.alignment = .center
        badge.translatesAutoresizingMaskIntoConstraints = false
        badgeBack.addSubview(badge)
        addSubview(badgeBack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 208),
            badgeBack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            badgeBack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            badgeBack.widthAnchor.constraint(equalToConstant: 28),
            badgeBack.heightAnchor.constraint(equalToConstant: 28),
            badge.centerXAnchor.constraint(equalTo: badgeBack.centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: badgeBack.centerYAnchor),
        ])
        applyState()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseUp(with event: NSEvent) { onClick() }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }

    // MARK: Keyboard

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        scrollToVisible(bounds.insetBy(dx: -8, dy: -8))   // the ring too
        return super.becomeFirstResponder()
    }
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " { onClick(); return }
        interpretKeyEvents([event])   // Tab, arrows, Enter; Esc reaches the panel
    }
    override func insertTab(_ sender: Any?) { window?.selectNextKeyView(self) }
    override func insertBacktab(_ sender: Any?) { window?.selectPreviousKeyView(self) }
    override func insertNewline(_ sender: Any?) { onCreate() }
    override func moveLeft(_ sender: Any?) { onMove(-1, 0) }
    override func moveRight(_ sender: Any?) { onMove(1, 0) }
    override func moveUp(_ sender: Any?) { onMove(0, -1) }
    override func moveDown(_ sender: Any?) { onMove(0, 1) }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16).fill() }
    override var focusRingMaskBounds: NSRect { bounds }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); applyState() }

    private func applyState() {
        let selected = position != nil
        badge.stringValue = position.map(String.init) ?? ""
        badgeBack.isHidden = !selected
        alphaValue = selected ? 1 : 0.72
        layer?.borderWidth = selected ? 3 : 1
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
            layer?.borderColor = (selected ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            badgeBack.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        }
        noteLabel.stringValue = baseNote ?? ""
        noteLabel.isHidden = baseNote == nil
        setAccessibilityValue(selected ? "Selected, number \(position!)" : "Not selected")
    }
}

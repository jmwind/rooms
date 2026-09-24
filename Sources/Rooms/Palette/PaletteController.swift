import AppKit
import RoomsCore

/// The floating field: type a room's name, press Enter, walk in.
@MainActor
final class PaletteController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    // Supplied by the app.
    var rooms: () -> [Room] = { [] }
    var loadError: () -> String? = { nil }
    var recency: () -> [String: Date] = { [:] }
    var currentRoomID: () -> String? = { nil }
    var willShow: () -> Void = {}
    var onChoose: (Room) -> Void = { _ in }
    var onSave: (String) -> Void = { _ in }
    /// The selected room changed (nil: nothing to preview).
    var onPreview: (Room?) -> Void = { _ in }
    var onLayoutChange: (Room, LayoutKind) -> Void = { _, _ in }
    /// The next layout worth trying for a room (forward or back), skipping ones that
    /// don't fit; nil when only one layout fits on this screen.
    var nextLayout: (Room, Bool) -> LayoutKind? = { room, forward in forward ? room.layout.next : room.layout.previous }
    /// The room's layout on the display you're working on.
    var layoutFor: (Room) -> LayoutKind = { $0.layout }
    /// The room's direct key (1 means ⌃⌥1), and assigning one with ⌘1…9.
    var shortcutFor: (Room) -> Int? = { _ in nil }
    var onAssignShortcut: (Room, Int) -> Void = { _, _ in }
    var onRemember: (Room) -> Void = { _ in }
    var onDelete: (Room) -> Void = { _ in }
    /// Brings back the last deleted room; false when there's nothing to undo.
    var onUndoDelete: () -> Bool = { false }
    /// The palette closed without walking into a room.
    var onCancel: () -> Void = {}
    /// Manual resize mode (⇧Tab): why it can't start on this room, or nil once it has.
    var beginAdjusting: (Room) -> String? = { _ in "There's nothing to adjust." }
    /// Lights the next separator.
    var adjustNext: () -> Void = {}
    /// Moves the lit separator by grid units (right/down positive); false when it can't.
    var adjustMove: (Int, Int) -> Bool = { _, _ in false }
    /// What the footer says while adjusting.
    var adjustingHint: () -> String = { "" }
    /// Leaves manual resize mode, keeping the result or not.
    var endAdjusting: (Bool) -> Void = { _ in }

    private enum Item {
        case room(Room)
        case save(String)
    }

    var isVisible: Bool { panel.isVisible }
    /// Where the panel is on screen (Cocoa coordinates), so previews can avoid it.
    var frame: CGRect? { panel.isVisible ? panel.frame : nil }

    private let width: CGFloat = 640
    private let maxRows = 7
    private let panel = PalettePanel()
    private let field = NSTextField()
    private let divider = NSBox()
    private let list = NSStackView()
    private let footerLeft = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var rows: [ResultRow] = []
    private var items: [Item] = []
    private var selected = 0
    private var isAdjusting = false
    /// Where the mouse was when the panel opened: a row that happens to be under a
    /// resting pointer mustn't take the selection from the room you're in.
    private var mouseAtShow: NSPoint?
    private var topEdge: CGFloat = 0
    private var iconCache: [String: NSImage] = [:]

    override init() {
        super.init()
        build()
    }

    func toggle() { isVisible ? hide() : show() }

    /// `selecting`: a room to start on (after its windows were chosen, so Tab and
    /// ⇧Tab can lay it out straight away); otherwise the most recent room.
    func show(selecting roomID: String? = nil) {
        willShow()
        field.stringValue = ""
        mouseAtShow = NSEvent.mouseLocation
        update()
        if let roomID, let i = items.firstIndex(where: { if case .room(let r) = $0 { r.id == roomID } else { false } }) { select(i) }
        position()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
                panel.animator().alphaValue = 1
            }
        }
    }

    /// `keepPreview`: Enter was pressed, so the layout preview stays up while the
    /// windows move underneath it, then fades (the app hides it).
    func hide(keepPreview: Bool = false) {
        guard panel.isVisible, !isClosing else { return }
        isClosing = true
        // Closing (Esc, clicking away) leaves an adjustment as it was; Enter and ⇧Tab keep it.
        if isAdjusting {
            isAdjusting = false
            endAdjusting(false)
        }
        panel.orderOut(nil)
        isClosing = false
        if !keepPreview { onCancel() }
    }

    private var isClosing = false

    /// Asks for the selected room's preview again (e.g. once the desk has been read).
    func refreshPreview() {
        guard panel.isVisible, selected < items.count, case .room(let room) = items[selected] else { return }
        onPreview(room)
    }

    // MARK: Building

    private func build() {
        panel.delegate = self
        panel.onCommandDelete = { [weak self] in
            guard let self, selected < items.count, case .room(let room) = items[selected] else { return }
            finishAdjusting(keep: true)
            delete(room)
        }
        panel.onCommandZ = { [weak self] in
            guard let self, onUndoDelete() else { return }
            finishAdjusting(keep: true)
            update(keepSelection: selected)
        }
        panel.onCommandS = { [weak self] in
            guard let self, selected < items.count, case .room(let room) = items[selected], !room.windows.isEmpty else { return }
            onRemember(room)
        }
        panel.onCommandE = { [weak self] in
            guard let self, selected < items.count, case .room(let room) = items[selected] else { return }
            hide()
            onSave(room.name)
        }
        panel.onCommandDigit = { [weak self] n in
            guard let self, selected < items.count, case .room(let room) = items[selected] else { return }
            finishAdjusting(keep: true)
            onAssignShortcut(room, n)
            update(keepSelection: selected)
        }

        // Field row
        let glyph = NSImageView(image: StatusIcon.doorway())
        glyph.contentTintColor = .secondaryLabelColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 24)
        field.placeholderString = "Go to a room"
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        field.setAccessibilityLabel("Room name")
        let fieldRow = NSStackView(views: [glyph, field])
        fieldRow.spacing = 12
        fieldRow.alignment = .centerY
        fieldRow.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        fieldRow.heightAnchor.constraint(equalToConstant: 56).isActive = true

        divider.boxType = .separator

        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 4

        // Footer
        footerLeft.font = .systemFont(ofSize: 12)
        footerLeft.textColor = .secondaryLabelColor
        let hints = NSTextField(labelWithString: "↵ Go    esc Close")
        hints.font = .systemFont(ofSize: 12)
        hints.textColor = .tertiaryLabelColor
        let footer = NSStackView(views: [footerLeft, NSView(), hints])
        footer.alignment = .centerY
        footer.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        footer.heightAnchor.constraint(equalToConstant: 32).isActive = true

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setViews([fieldRow, divider, list, footer], in: .top)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for v in [fieldRow, divider, list, footer] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])

        // One glass surface on macOS 26; a matching material before that.
        if let glass = Glass.surface(container) {
            panel.contentView = glass
            // Glass draws its own edge; the window's rectangular shadow would show behind the corners.
            panel.hasShadow = false
        } else {
            let material = NSVisualEffectView()
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = 24
            material.layer?.masksToBounds = true
            container.translatesAutoresizingMaskIntoConstraints = false
            material.addSubview(container)
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: material.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: material.trailingAnchor),
                container.topAnchor.constraint(equalTo: material.topAnchor),
                container.bottomAnchor.constraint(equalTo: material.bottomAnchor),
            ])
            panel.contentView = material
        }
    }

    // MARK: Results

    private func update(keepSelection: Int = 0) {
        let query = field.stringValue
        rows.forEach { $0.removeFromSuperview() }
        rows = []

        items = []
        if let error = loadError() {
            rows = [ResultRow(title: "rooms.json has a problem", detail: error, icons: [], accessory: nil, interactive: false)]
        } else {
            let all = rooms()
            let matches = Matcher.rank(query, rooms: all, recency: recency()).prefix(maxRows)
            let current = currentRoomID()
            for match in matches {
                let room = match.room
                let index = rows.count
                // The icons already show which apps; the words stay short.
                let count = room.windows.isEmpty
                    ? (room.apps.isEmpty ? "No apps yet" : (room.apps.count == 1 ? "1 app" : "\(room.apps.count) apps"))
                    : (room.windows.count == 1 ? "1 window" : "\(room.windows.count) windows")
                let detail = [room.kind, count].compactMap { $0 }.joined(separator: " · ")
                var bundles: [String] = []
                for id in room.windows.map(\.bundleID) + room.apps.map(\.bundleID) where !bundles.contains(id) { bundles.append(id) }
                items.append(.room(room))
                rows.append(ResultRow(title: room.name, detail: detail, icons: bundles.compactMap(icon),
                                      accessory: Optional([room.id == current ? "Current" : nil, shortcutFor(room).map { "⌃⌥\($0)" }]
                                          .compactMap { $0 }.joined(separator: "   ")).flatMap { $0.isEmpty ? nil : $0 }, interactive: true))
                rows[index].onDelete = { [weak self] in self?.delete(room) }
                rows[index].onEdit = { [weak self] in
                    self?.hide()
                    self?.onSave(room.name)
                }
            }

            // Any name can become a room: pick its windows. An existing name edits that room.
            let name = query.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                let existing = all.first { Matcher.fold($0.name) == Matcher.fold(name) }
                    ?? matches.first.map(\.room).flatMap { $0.aliases.contains { Matcher.fold($0) == Matcher.fold(name) } ? $0 : nil }
                let symbol = NSImage(systemSymbolName: "plus.rectangle.on.rectangle", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
                items.append(.save(existing?.name ?? name))
                rows.append(ResultRow(
                    title: existing.map { "Choose windows for “\($0.name)”…" } ?? "New room “\(RoomTemplate.matching(name)?.name ?? name)”…",
                    detail: existing.map { _ in "Pick which open windows belong in it" }
                        ?? (RoomTemplate.matching(name) != nil ? "Template · starts with a description" : "Pick the open windows that belong in it"),
                    icons: symbol.map { [$0] } ?? [], accessory: nil, interactive: true))
            }
            if rows.isEmpty {
                rows = [ResultRow(title: "No rooms yet", detail: "Type a name to save this desk as a room", icons: [], accessory: nil, interactive: false)]
            }
        }

        for (i, row) in rows.enumerated() {
            row.onHover = { [weak self] in
                guard let self else { return }
                if let at = mouseAtShow { guard NSEvent.mouseLocation != at else { return }; mouseAtShow = nil }
                select(i)
            }
            row.onClick = { [weak self] in
                self?.finishAdjusting(keep: true)
                self?.select(i)
                self?.choose()
            }
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        selected = min(keepSelection, max(items.count - 1, 0))
        refreshSelection()
        resize()
    }

    private func select(_ i: Int) {
        // While adjusting, the mouse passing over another row mustn't switch rooms.
        guard !isAdjusting, i >= 0, i < items.count, i != selected || rows.first(where: \.isSelected) == nil else { return }
        selected = i
        refreshSelection()
    }

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        select((selected + delta + items.count) % items.count)
    }

    /// One click (or ⌘⌫) deletes; ⌘Z brings it back. Its windows are never touched.
    private func delete(_ room: Room) {
        onDelete(room)
        update(keepSelection: max(0, selected - 1))
        footerLeft.stringValue = "Deleted “\(room.name)”. Its windows stay open.    ⌘Z Undo"
    }

    private func refreshSelection() {
        footerLeft.textColor = .secondaryLabelColor
        for (i, row) in rows.enumerated() { row.isSelected = (i == selected && !items.isEmpty) }
        let room: Room? = if selected < items.count, case .room(let r) = items[selected] { r } else { nil }

        // The footer names the layout of the selected room; Tab changes it, ⇧Tab adjusts it.
        if let room, !room.windows.isEmpty {
            footerLeft.stringValue = "Here: \(layoutFor(room).title)    ⇥ Layout    ⇧⇥ Adjust    ⌘E Windows    ⌘S Remember    ⌘1–9 Key"
        } else if let id = currentRoomID(), let current = rooms().first(where: { $0.id == id }) {
            footerLeft.stringValue = "In \(current.name)"
        } else {
            let count = rooms().count
            footerLeft.stringValue = count == 1 ? "1 room" : "\(count) rooms"
        }
        onPreview(room)
    }

    /// Tab: try the next layout on the selected room, live.
    private func cycleLayout() {
        guard selected < items.count, case .room(let room) = items[selected], !room.windows.isEmpty else { return }
        guard let kind = nextLayout(room, true) else {
            // Say so, rather than Tab seeming to do nothing.
            footerLeft.stringValue = "Only one layout fits these windows on this screen."
            NSSound.beep()
            return
        }
        onLayoutChange(room, kind)
        update(keepSelection: selected)
    }

    // MARK: Manual resize mode

    /// ⇧Tab: the layout's separators light up one at a time in the preview, the arrow
    /// keys move the lit one, and ⇧Tab again keeps the result as My Layout.
    private func startAdjusting() {
        guard selected < items.count, case .room(let room) = items[selected], !room.windows.isEmpty else { return }
        if let why = beginAdjusting(room) {
            // Say why, rather than ⇧Tab seeming to do nothing.
            footerLeft.stringValue = why
            NSSound.beep()
            return
        }
        isAdjusting = true
        refreshAdjusting()
    }

    private func finishAdjusting(keep: Bool) {
        guard isAdjusting else { return }
        isAdjusting = false
        endAdjusting(keep)
        update(keepSelection: selected)
    }

    /// An arrow key: moves the lit separator (a beep when it can't go further).
    private func nudge(_ dx: Int, _ dy: Int) {
        if !adjustMove(dx, dy) { NSSound.beep() }
        refreshAdjusting()
    }

    private func refreshAdjusting() {
        footerLeft.stringValue = adjustingHint()
        if selected < items.count, case .room(let room) = items[selected] { onPreview(room) }
    }

    private func choose() {
        finishAdjusting(keep: true)   // Enter keeps an adjustment, then walks in
        guard selected < items.count else { return }
        let item = items[selected]
        switch item {
        case .room(let room):
            hide(keepPreview: true)
            onChoose(room)
        case .save(let name):
            hide()
            onSave(name)
        }
    }

    // MARK: Geometry

    private func position() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        topEdge = visible.maxY - visible.height * 0.2
        let height = panel.frame.height
        panel.setFrame(NSRect(x: visible.midX - width / 2, y: topEdge - height, width: width, height: height), display: true)
    }

    private func resize() {
        stack.layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height + 24
        let top = panel.isVisible ? panel.frame.maxY : (topEdge == 0 ? panel.frame.maxY : topEdge)
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - height, width: width, height: height), display: true)
    }

    // MARK: App info

    private func icon(_ bundleID: String) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 24, height: 24)
        iconCache[bundleID] = image
        return image
    }

    // MARK: NSTextFieldDelegate / NSWindowDelegate

    func controlTextDidChange(_ obj: Notification) {
        // Don't filter mid-composition (dead keys, input methods).
        if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
        // Typing moves on to another room; an adjustment made so far is kept.
        if isAdjusting {
            isAdjusting = false
            endAdjusting(true)
        }
        update()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let big = Separators.twelfth
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            if isAdjusting { nudge(0, 1) } else { move(1) }
            return true
        case #selector(NSResponder.moveUp(_:)):
            if isAdjusting { nudge(0, -1) } else { move(-1) }
            return true
        // Left and right move the caret unless a separator is lit.
        case #selector(NSResponder.moveLeft(_:)):
            guard isAdjusting else { return false }
            nudge(-1, 0); return true
        case #selector(NSResponder.moveRight(_:)):
            guard isAdjusting else { return false }
            nudge(1, 0); return true
        // ⇧ + arrow: a twelfth of the screen at a time.
        case #selector(NSResponder.moveLeftAndModifySelection(_:)):
            guard isAdjusting else { return false }
            nudge(-big, 0); return true
        case #selector(NSResponder.moveRightAndModifySelection(_:)):
            guard isAdjusting else { return false }
            nudge(big, 0); return true
        case #selector(NSResponder.moveUpAndModifySelection(_:)):
            guard isAdjusting else { return false }
            nudge(0, -big); return true
        case #selector(NSResponder.moveDownAndModifySelection(_:)):
            guard isAdjusting else { return false }
            nudge(0, big); return true
        case #selector(NSResponder.insertTab(_:)):
            if isAdjusting { adjustNext(); refreshAdjusting() } else { cycleLayout() }
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            if isAdjusting { finishAdjusting(keep: true) } else { startAdjusting() }
            return true
        case #selector(NSResponder.insertNewline(_:)):
            choose(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide(); return true
        default:
            return false
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

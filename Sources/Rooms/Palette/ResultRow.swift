import AppKit

/// One line in the palette: the room's app icons, its name, and what it holds.
final class ResultRow: NSView {
    var onHover: (() -> Void)?
    var onClick: (() -> Void)?
    /// Room rows only: the ⓧ shown on the selected row, and the right-click menu.
    var onDelete: (() -> Void)? { didSet { deleteButton.isHidden = !(isSelected && onDelete != nil) } }
    var onEdit: (() -> Void)?
    var isSelected = false { didSet { if isSelected != oldValue { applyColors() } } }

    let isInteractive: Bool
    private let nameLabel: NSTextField
    private let detailLabel: NSTextField
    private let accessoryLabel = NSTextField(labelWithString: "")
    private let accessoryText: String?
    private var tracking: NSTrackingArea?
    private let deleteButton = NSButton()

    init(title: String, detail: String?, icons: [NSImage], accessory: String?, interactive: Bool) {
        isInteractive = interactive
        accessoryText = accessory
        nameLabel = NSTextField(labelWithString: title)
        detailLabel = NSTextField(labelWithString: detail ?? "")
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 48).isActive = true

        nameLabel.font = .systemFont(ofSize: 14)
        nameLabel.lineBreakMode = .byTruncatingTail
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.isHidden = (detail ?? "").isEmpty
        accessoryLabel.font = .systemFont(ofSize: 12)
        accessoryLabel.alignment = .right

        let text = NSStackView(views: [nameLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0

        // App icons overlap slightly, like a small hand of cards.
        let iconStack = NSStackView(views: icons.prefix(4).map { image in
            let v = NSImageView(image: image)
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalToConstant: 24).isActive = true
            v.heightAnchor.constraint(equalToConstant: 24).isActive = true
            return v
        })
        iconStack.spacing = -8
        iconStack.translatesAutoresizingMaskIntoConstraints = false
        iconStack.widthAnchor.constraint(equalToConstant: 72).isActive = true
        iconStack.alignment = .centerY

        // Delete, the way Safari removes a Favorite: an ⓧ on the row you're on.
        deleteButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Delete Room")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        deleteButton.isBordered = false
        deleteButton.imagePosition = .imageOnly
        deleteButton.toolTip = "Delete Room (its windows stay open)"
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        deleteButton.isHidden = true
        deleteButton.setAccessibilityLabel("Delete Room")

        let row = NSStackView(views: [iconStack, text, NSView(), accessoryLabel, deleteButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 16)
        row.translatesAutoresizingMaskIntoConstraints = false
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        guard isInteractive else { return }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) { if !isSelected { onHover?() } }
    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseUp(with event: NSEvent) { if isInteractive { onClick?() } }

    @objc private func deleteClicked() { onDelete?() }
    @objc private func editClicked() { onEdit?() }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard onDelete != nil else { return nil }
        let menu = NSMenu()
        if onEdit != nil { menu.addItem(withTitle: "Edit Windows…", action: #selector(editClicked), keyEquivalent: "").target = self }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Delete Room", action: #selector(deleteClicked), keyEquivalent: "").target = self
        return menu
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        let selected = isSelected && isInteractive
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = selected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        }
        nameLabel.textColor = selected ? .alternateSelectedControlTextColor : (isInteractive ? .labelColor : .secondaryLabelColor)
        detailLabel.textColor = selected ? .alternateSelectedControlTextColor.withAlphaComponent(0.8) : .secondaryLabelColor
        accessoryLabel.textColor = selected ? .alternateSelectedControlTextColor : .tertiaryLabelColor
        accessoryLabel.stringValue = selected ? (accessoryText.map { $0 + "    ↵" } ?? "↵") : (accessoryText ?? "")
        deleteButton.isHidden = !(selected && onDelete != nil)
        deleteButton.contentTintColor = selected ? .alternateSelectedControlTextColor.withAlphaComponent(0.8) : .tertiaryLabelColor
    }
}

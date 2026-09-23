import AppKit

/// A short message at the bottom of the screen: "Saved Design · 5 windows".
/// Glass capsule, click-through, gone after a moment.
@MainActor
final class Toast {
    private var window: NSPanel?
    private var hideWork: DispatchWorkItem?
    /// 16 above and below, 24 at the sides: even to the eye on a short, wide pill.
    private let padding = NSEdgeInsets(top: 16, left: 24, bottom: 16, right: 24)
    private let maxWidth: CGFloat = 560
    private let spacing: CGFloat = 4

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = .center
        return field
    }

    /// The text's size on one line, or wrapped at `maxWidth` when it's longer.
    private func measure(_ field: NSTextField, maxWidth: CGFloat) -> CGSize {
        let size = field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: maxWidth, height: .greatestFiniteMagnitude)) ?? .zero
        return CGSize(width: ceil(min(size.width, maxWidth)), height: ceil(size.height))
    }

    func show(_ text: String, detail: String? = nil) {
        let panel = window ?? makePanel()
        window = panel

        // Laid out by hand, not by Auto Layout: measure the text (wrapping long
        // messages), then add exactly `padding` around it. Glass sizes its content
        // unreliably, which let long messages run edge to edge.
        let maxText = maxWidth - padding.left - padding.right
        let title = label(text, font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor)
        let sub = label(detail ?? "", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        let hasDetail = !(detail ?? "").isEmpty
        let titleSize = measure(title, maxWidth: maxText)
        let subSize = hasDetail ? measure(sub, maxWidth: maxText) : .zero
        let textWidth = max(titleSize.width, subSize.width)
        let width = textWidth + padding.left + padding.right
        let height = padding.top + titleSize.height + (hasDetail ? spacing + subSize.height : 0) + padding.bottom

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        title.frame = NSRect(x: padding.left, y: height - padding.top - titleSize.height, width: textWidth, height: titleSize.height)
        content.addSubview(title)
        if hasDetail {
            sub.frame = NSRect(x: padding.left, y: padding.bottom, width: textWidth, height: subSize.height)
            content.addSubview(sub)
        }

        let background: NSView
        // Tinted so the pill reads as floating above the windows; clear glass over a
        // busy window shows its text through and looks like it's behind it.
        if let glass = Glass.surface(content, tint: NSColor.windowBackgroundColor.withAlphaComponent(0.85)) {
            background = glass
        } else {
            let material = NSVisualEffectView(frame: content.frame)
            material.material = .popover
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = 24
            material.layer?.masksToBounds = true
            material.addSubview(content)
            background = material
        }
        panel.contentView = background

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let v = screen.visibleFrame
        panel.setFrame(NSRect(x: v.midX - width / 2, y: v.minY + 48, width: width, height: height), display: true)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
        }

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 },
                                                 completionHandler: { MainActor.assumeIsolated { panel.orderOut(nil) } })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (detail == nil ? 2.2 : 3.5), execute: work)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.isReleasedWhenClosed = false
        return p
    }
}

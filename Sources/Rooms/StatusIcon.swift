import AppKit

/// The doorway mark (design/menu-bar-icon.svg): the menu bar icon, and the glyph
/// beside the palette's field.
enum StatusIcon {
    static func doorway() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            path.move(to: NSPoint(x: 4, y: 15.5))
            path.line(to: NSPoint(x: 4, y: 2.5))
            path.line(to: NSPoint(x: 14, y: 2.5))
            path.line(to: NSPoint(x: 14, y: 15.5))

            path.move(to: NSPoint(x: 4, y: 2.5))
            path.line(to: NSPoint(x: 10.5, y: 4.5))
            path.line(to: NSPoint(x: 10.5, y: 16))
            path.line(to: NSPoint(x: 4, y: 14))

            path.move(to: NSPoint(x: 8.3, y: 9.3))
            path.line(to: NSPoint(x: 8.3, y: 10))
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Rooms"
        return image
    }
}

import AppKit

/// macOS 26's glass surface, when there is one. Looked up by name at run time rather
/// than compiled in, so Rooms still builds with an older SDK (Xcode 16) and falls back
/// to a frosted material there.
@MainActor
enum Glass {
    /// `content` on glass with rounded corners, or nil before macOS 26. `tint` makes
    /// the glass more solid, for things that sit over busy windows (the toast).
    static func surface(_ content: NSView, cornerRadius: CGFloat = 24, tint: NSColor? = nil) -> NSView? {
        guard let type = NSClassFromString("NSGlassEffectView") as? NSView.Type else { return nil }
        let glass = type.init(frame: .zero)
        glass.setValue(cornerRadius, forKey: "cornerRadius")
        if let tint { glass.setValue(tint, forKey: "tintColor") }
        glass.setValue(content, forKey: "contentView")
        return glass
    }
}

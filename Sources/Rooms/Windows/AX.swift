import AppKit
import ApplicationServices

/// Thin helpers over the Accessibility API. Everything runs on the main actor:
/// AXUIElement isn't Sendable, and every call is a short IPC round-trip.
enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to Privacy & Security › Accessibility.
    static func requestTrust() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func app(_ pid: pid_t) -> AXUIElement {
        let el = AXUIElementCreateApplication(pid)
        // A hung app must never freeze Rooms (the default timeout is ~6 s).
        AXUIElementSetMessagingTimeout(el, 0.5)
        return el
    }

    static func attribute<T>(_ el: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func elements(_ el: AXUIElement, _ name: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success,
              let array = value as? [AnyObject] else { return [] }
        return array.map { $0 as! AXUIElement }
    }

    static func frame(_ el: AXUIElement) -> CGRect? {
        var pos = CGPoint.zero, size = CGSize.zero
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s) == .success,
              let p, let s,
              AXValueGetValue(p as! AXValue, .cgPoint, &pos),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    /// Size, then position, then size again: macOS clamps size to the display a window
    /// is currently on, so a move to another display needs the second resize (Rectangle).
    static func setFrame(_ el: AXUIElement, _ r: CGRect) {
        setSize(el, r.size)
        setPosition(el, r.origin)
        setSize(el, r.size)
    }

    static func setPosition(_ el: AXUIElement, _ point: CGPoint) {
        var p = point
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v) }
    }

    static func setSize(_ el: AXUIElement, _ size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v) }
    }

    static func setBool(_ el: AXUIElement, _ name: String, _ value: Bool) {
        AXUIElementSetAttributeValue(el, name as CFString, (value ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
    }

    static func raise(_ el: AXUIElement) {
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
    }

    /// The window-server ID for an AX window, via the private `_AXUIElementGetWindow`
    /// that every macOS window manager uses. Looked up at runtime so a future macOS
    /// without it degrades to title matching instead of crashing.
    static func windowID(_ el: AXUIElement) -> CGWindowID? {
        guard let getWindow = getWindowFunction else { return nil }
        var id: CGWindowID = 0
        return getWindow(el, &id) == .success && id != 0 ? id : nil
    }

    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindowFunction: GetWindowFunction? = {
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: GetWindowFunction.self)
    }()
}

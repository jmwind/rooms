import AppKit
import RoomsCore

/// Displays in Accessibility coordinates (top-left origin of the primary display).
struct ScreenInfo {
    let uuid: String
    let frame: CGRect
    let visible: CGRect

    @MainActor
    static func all() -> [ScreenInfo] {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.map { screen in
            ScreenInfo(
                uuid: uuid(of: screen),
                frame: Geometry.axRect(fromCocoa: screen.frame, primaryHeight: primaryHeight),
                visible: Geometry.axRect(fromCocoa: screen.visibleFrame, primaryHeight: primaryHeight)
            )
        }
    }

    @MainActor
    private static func uuid(of screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let cf = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, cf) else { return "unknown" }
        return string as String
    }
}

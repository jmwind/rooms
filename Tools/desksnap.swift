// desksnap save <file> | restore <file>
// Records every window's frame and which apps are hidden, and puts them back. A safety
// net for testing Rooms on a real desk.
import AppKit
import ApplicationServices

typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
let getWindow = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow"), to: GetWindow.self)

struct Win: Codable { var pid: Int32; var id: UInt32; var title: String; var x, y, w, h: Double }
struct Desk: Codable { var windows: [Win]; var hiddenPIDs: [Int32]; var frontPID: Int32? }

func windows(_ pid: pid_t) -> [AXUIElement] {
    let el = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(el, 1)
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXWindowsAttribute as CFString, &v) == .success else { return [] }
    return (v as? [AXUIElement]) ?? []
}
func frame(_ el: AXUIElement) -> CGRect? {
    var p: CFTypeRef?, s: CFTypeRef?; var pt = CGPoint.zero, sz = CGSize.zero
    guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p) == .success,
          AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s) == .success,
          AXValueGetValue(p as! AXValue, .cgPoint, &pt), AXValueGetValue(s as! AXValue, .cgSize, &sz) else { return nil }
    return CGRect(origin: pt, size: sz)
}
let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
let args = CommandLine.arguments
guard args.count == 3 else { print("usage: desksnap save|restore <file>"); exit(1) }
let url = URL(fileURLWithPath: args[2])

if args[1] == "save" {
    var desk = Desk(windows: [], hiddenPIDs: apps.filter(\.isHidden).map(\.processIdentifier),
                    frontPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    for app in apps {
        for w in windows(app.processIdentifier) {
            var id: CGWindowID = 0; _ = getWindow(w, &id)
            var t: CFTypeRef?; AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
            guard let f = frame(w) else { continue }
            desk.windows.append(Win(pid: app.processIdentifier, id: id, title: t as? String ?? "", x: f.minX, y: f.minY, w: f.width, h: f.height))
        }
    }
    try! JSONEncoder().encode(desk).write(to: url)
    print("saved \(desk.windows.count) windows, \(desk.hiddenPIDs.count) hidden apps")
} else {
    let desk = try! JSONDecoder().decode(Desk.self, from: Data(contentsOf: url))
    let byID = Dictionary(desk.windows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    for app in apps where !desk.hiddenPIDs.contains(app.processIdentifier) { app.unhide() }
    usleep(300_000)
    var restored = 0
    for app in apps {
        for w in windows(app.processIdentifier) {
            var id: CGWindowID = 0; _ = getWindow(w, &id)
            guard let s = byID[id] else { continue }
            var size = CGSize(width: s.w, height: s.h), pos = CGPoint(x: s.x, y: s.y)
            AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
            AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &pos)!)
            AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
            restored += 1
        }
    }
    // Never hide the app the keyboard is talking to, and hand focus back to the app
    // that was in front before the test. (Hiding the active app once left typing
    // going nowhere.)
    let activeNow = NSWorkspace.shared.frontmostApplication?.processIdentifier
    for app in apps where desk.hiddenPIDs.contains(app.processIdentifier) && app.processIdentifier != activeNow && app.processIdentifier != desk.frontPID {
        app.hide()
    }
    if let pid = desk.frontPID, let front = NSRunningApplication(processIdentifier: pid) {
        front.unhide()
        front.activate()
    }
    print("restored \(restored) windows")
}

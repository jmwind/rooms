import AppKit
import ScreenCaptureKit
import RoomsCore

/// Small pictures of windows for the layout preview, so a room's cards show the
/// windows themselves rather than their apps' icons. A window keeps its number for
/// as long as it's open, so one picture per window is taken (while it's on screen:
/// macOS draws nothing for a hidden app's windows) and kept in
/// ~/Library/Application Support/Rooms/previews for a week, across launches. Needs
/// Screen Recording, asked for once; Window Previews off in the menu deletes the lot.
@MainActor
final class Thumbnails {
    /// Whether previews are wanted (the menu's Window Previews item).
    var enabled: () -> Bool = { true }

    static let folder = RoomStore.defaultURL.deletingLastPathComponent().appending(path: "previews", directoryHint: .isDirectory)
    /// After this, a window's picture is taken again the next time it's on screen.
    private let keepFor: TimeInterval = 7 * 24 * 3600
    /// When ⌥Space opens, pictures of the windows on screen older than this are
    /// retaken, so a card shows a window roughly as you last left it.
    static let refreshAfter: TimeInterval = 5 * 60
    /// The longest side of a picture, in points: enough for a card, small on disk.
    private let longestSide: CGFloat = 640

    /// Pictures on disk, by window number, with the app they belong to (a number can
    /// come round again after a restart, so the app has to match too).
    private var files: [CGWindowID: (bundleID: String, url: URL, taken: Date)] = [:]
    private var images: [CGWindowID: NSImage] = [:]
    private var asked = UserDefaults.standard.bool(forKey: "askedForScreenRecording")
    private var capturing = false

    init() { load() }

    /// Reads the folder: "<bundle id>-<window number>.jpg", dropping old pictures.
    private func load() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for url in urls where url.pathExtension == "jpg" {
            let name = url.deletingPathExtension().lastPathComponent
            guard let dash = name.lastIndex(of: "-"), let id = CGWindowID(name[name.index(after: dash)...]) else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if Date().timeIntervalSince(modified) > keepFor {
                try? fm.removeItem(at: url)
                continue
            }
            files[id] = (String(name[..<dash]), url, modified)
        }
    }

    func image(for id: CGWindowID?, of bundleID: String) -> NSImage? {
        guard enabled(), let id else { return nil }
        if let image = images[id] { return image }
        guard let file = files[id], file.bundleID == bundleID, let image = NSImage(contentsOf: file.url) else { return nil }
        images[id] = image
        return image
    }

    /// Whether macOS lets Rooms read the screen right now.
    var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt again and opens the Screen Recording settings.
    func askAgain() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Whether macOS lets Rooms read the screen. Asks once, the first time previews are
    /// wanted; after allowing it, macOS applies the permission on the next launch.
    private func allowed() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        guard !asked else { return false }
        asked = true
        UserDefaults.standard.set(true, forKey: "askedForScreenRecording")
        CGRequestScreenCaptureAccess()
        return false
    }

    /// Takes pictures of the windows among these that are on screen now and have none
    /// yet, or (with `olderThan`) one older than that. One round at a time; a call while
    /// one runs is skipped (the next opening of the palette catches up).
    func capture(_ windows: [(id: CGWindowID, bundleID: String)], olderThan age: TimeInterval? = nil) async {
        let stale = { (id: CGWindowID) -> Bool in
            guard let file = self.files[id] else { return true }
            return age.map { Date().timeIntervalSince(file.taken) > $0 } ?? false
        }
        let wanted = Dictionary(windows.filter { stale($0.id) }.map { ($0.id, $0.bundleID) }, uniquingKeysWith: { a, _ in a })
        guard enabled(), !wanted.isEmpty, !capturing else { return }
        guard allowed() else { Log.file("Previews: \(wanted.count) wanted, but Screen Recording isn't allowed"); return }
        capturing = true
        defer { capturing = false }
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) } catch {
            Log.file("Previews: couldn't list windows: \(error.localizedDescription)")
            return
        }
        var taken = 0
        defer { Log.file("Previews: \(taken) of \(wanted.count) wanted taken") }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        for window in content.windows where wanted[window.windowID] != nil && window.frame.width >= 100 && window.frame.height >= 60 {
            let scale = min(1, longestSide / max(window.frame.width, window.frame.height))
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            let filter = SCContentFilter(desktopIndependentWindow: window)
            guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { continue }
            let size = NSSize(width: window.frame.width * scale, height: window.frame.height * scale)
            images[window.windowID] = NSImage(cgImage: cg, size: size)
            taken += 1
            let bundleID = wanted[window.windowID] ?? ""
            let url = Self.folder.appending(path: "\(bundleID)-\(window.windowID).jpg")
            if let data = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.7]),
               (try? data.write(to: url, options: .atomic)) != nil {
                files[window.windowID] = (bundleID, url, Date())
            }
        }
    }

    /// Window Previews turned off: nothing kept.
    func forgetAll() {
        images = [:]
        files = [:]
        try? FileManager.default.removeItem(at: Self.folder)
    }
}

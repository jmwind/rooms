import AppKit

/// A floating panel that takes keystrokes without activating Rooms, so the app you
/// were in keeps its menu bar and focus returns to it when the panel closes.
final class PalettePanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 80),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
    }

    /// ⌘1…⌘9: give the selected room that direct key.
    var onCommandDigit: ((Int) -> Void)?
    /// ⌘S: remember the selected room's current arrangement.
    var onCommandS: (() -> Void)?
    /// ⌘↩: walk into the selected room, bringing the window you're in.
    var onCommandReturn: (() -> Void)?
    /// ⌘⌫: delete the selected room.
    var onCommandDelete: (() -> Void)?
    /// ⌘Z: bring back the room just deleted.
    var onCommandZ: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let c = event.charactersIgnoringModifiers, let n = Int(c), (1...9).contains(n) {
            onCommandDigit?(n)
            return true
        }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.keyCode == 36 { // ↩
            onCommandReturn?()
            return true
        }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.keyCode == 51 { // ⌫
            onCommandDelete?()
            return true
        }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "z",
           let onCommandZ, !(firstResponder is NSTextView && (firstResponder as? NSTextView)?.undoManager?.canUndo == true) {
            onCommandZ()
            return true
        }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "s" {
            onCommandS?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override var canBecomeMain: Bool { false }
}

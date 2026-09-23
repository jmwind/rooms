import AppKit
import Carbon.HIToolbox
import RoomsCore

/// The snapping keys: Rectangle's defaults, so muscle memory carries over.
enum SnapCommand {
    case snap(SnapAction)
    case restore
    case display(Int)

    var title: String {
        switch self {
        case .snap(let a): a.title
        case .restore: "Restore"
        case .display(let d): d > 0 ? "Next Display" : "Previous Display"
        }
    }
}

struct SnapBinding {
    let command: SnapCommand
    let shortcut: Shortcut
    /// For showing the key in a menu.
    let menuKey: String
    let menuModifiers: NSEvent.ModifierFlags

    static let all: [SnapBinding] = {
        let co = UInt32(controlKey | optionKey), coc = UInt32(controlKey | optionKey | cmdKey)
        func arrow(_ c: Int) -> String { String(UnicodeScalar(c)!) }
        func b(_ cmd: SnapCommand, _ code: Int, _ mods: UInt32, _ key: String, _ symbol: String) -> SnapBinding {
            let m: NSEvent.ModifierFlags = mods == coc ? [.control, .option, .command] : [.control, .option]
            return SnapBinding(command: cmd, shortcut: Shortcut(id: "snap-\(cmd.title)", keyCode: UInt32(code), modifiers: mods,
                                                                 label: (mods == coc ? "⌃⌥⌘" : "⌃⌥") + symbol),
                               menuKey: key, menuModifiers: m)
        }
        return [
            b(.snap(.leftHalf), kVK_LeftArrow, co, arrow(NSLeftArrowFunctionKey), "←"),
            b(.snap(.rightHalf), kVK_RightArrow, co, arrow(NSRightArrowFunctionKey), "→"),
            b(.snap(.topHalf), kVK_UpArrow, co, arrow(NSUpArrowFunctionKey), "↑"),
            b(.snap(.bottomHalf), kVK_DownArrow, co, arrow(NSDownArrowFunctionKey), "↓"),
            b(.snap(.topLeft), kVK_ANSI_U, co, "u", "U"),
            b(.snap(.topRight), kVK_ANSI_I, co, "i", "I"),
            b(.snap(.bottomLeft), kVK_ANSI_J, co, "j", "J"),
            b(.snap(.bottomRight), kVK_ANSI_K, co, "k", "K"),
            b(.snap(.firstThird), kVK_ANSI_D, co, "d", "D"),
            b(.snap(.centerThird), kVK_ANSI_F, co, "f", "F"),
            b(.snap(.lastThird), kVK_ANSI_G, co, "g", "G"),
            b(.snap(.firstTwoThirds), kVK_ANSI_E, co, "e", "E"),
            b(.snap(.lastTwoThirds), kVK_ANSI_T, co, "t", "T"),
            b(.snap(.maximize), kVK_Return, co, "\r", "↩"),
            b(.snap(.center), kVK_ANSI_C, co, "c", "C"),
            b(.restore, kVK_Delete, co, "\u{8}", "⌫"),
            b(.display(1), kVK_RightArrow, coc, arrow(NSRightArrowFunctionKey), "→"),
            b(.display(-1), kVK_LeftArrow, coc, arrow(NSLeftArrowFunctionKey), "←"),
        ]
    }()
}

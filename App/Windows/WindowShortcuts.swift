import AppKit
import Carbon.HIToolbox
import PEACore

/// A global shortcut for a window action. The set is Magnet's defaults:
/// ⌃⌥ plus an arrow, a letter, ↩ or ⌫, and ⌃⌥⌘ ← → for other displays.
struct WindowShortcut {
    let action: WindowAction
    let key: HotKey
    /// Shown in Settings, after the modifiers.
    let keySymbol: String
    /// For the menu item, which draws the modifiers itself.
    let keyEquivalent: String
    var command = false

    var modifierFlags: NSEvent.ModifierFlags {
        command ? [.control, .option, .command] : [.control, .option]
    }

    var carbonModifiers: UInt32 {
        UInt32(controlKey | optionKey) | (command ? UInt32(cmdKey) : 0)
    }

    var symbols: String { (command ? "⌃⌥⌘" : "⌃⌥") + keySymbol }

    /// Grouped the way Settings and the menu show them.
    static let groups: [WindowShortcutGroup] = [
        WindowShortcutGroup(title: "Halves", shortcuts: [
            arrow(.leftHalf, kVK_LeftArrow, "←", NSLeftArrowFunctionKey),
            arrow(.rightHalf, kVK_RightArrow, "→", NSRightArrowFunctionKey),
            arrow(.topHalf, kVK_UpArrow, "↑", NSUpArrowFunctionKey),
            arrow(.bottomHalf, kVK_DownArrow, "↓", NSDownArrowFunctionKey),
        ]),
        WindowShortcutGroup(title: "Quarters", shortcuts: [
            letter(.topLeft, "u"),
            letter(.topRight, "i"),
            letter(.bottomLeft, "j"),
            letter(.bottomRight, "k"),
        ]),
        WindowShortcutGroup(title: "Thirds", shortcuts: [
            letter(.leftThird, "d"),
            letter(.centerThird, "f"),
            letter(.rightThird, "g"),
            letter(.leftTwoThirds, "e"),
            letter(.rightTwoThirds, "t"),
        ]),
        WindowShortcutGroup(title: "Size", shortcuts: [
            WindowShortcut(action: .maximize, key: .code(kVK_Return), keySymbol: "↩", keyEquivalent: "\r"),
            letter(.center, "c"),
            WindowShortcut(action: .restore, key: .code(kVK_Delete), keySymbol: "⌫", keyEquivalent: "\u{8}"),
        ]),
        WindowShortcutGroup(title: "Displays", shortcuts: [
            arrow(.previousDisplay, kVK_LeftArrow, "←", NSLeftArrowFunctionKey, command: true),
            arrow(.nextDisplay, kVK_RightArrow, "→", NSRightArrowFunctionKey, command: true),
        ]),
    ]

    static var all: [WindowShortcut] { groups.flatMap(\.shortcuts) }

    private static func arrow(
        _ action: WindowAction, _ code: Int, _ symbol: String, _ functionKey: Int, command: Bool = false
    ) -> WindowShortcut {
        let equivalent = UnicodeScalar(UInt32(functionKey)).map { String(Character($0)) } ?? ""
        return WindowShortcut(action: action, key: .code(code), keySymbol: symbol, keyEquivalent: equivalent, command: command)
    }

    private static func letter(_ action: WindowAction, _ character: Character) -> WindowShortcut {
        WindowShortcut(
            action: action, key: .character(character),
            keySymbol: String(character).uppercased(), keyEquivalent: String(character)
        )
    }
}

struct WindowShortcutGroup {
    let title: String
    let shortcuts: [WindowShortcut]
}

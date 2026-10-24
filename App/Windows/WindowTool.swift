import AppKit
import PEACore
import SwiftUI

@MainActor
final class WindowTool: NSObject, PEATool {
    let id = "windows"
    let title = "Windows"
    let settingsSymbol = "rectangle.split.2x1"
    let statusMenuTitle: String? = "Move Window"

    private let prefs: Preferences
    private let windows = WindowManager()

    init(prefs: Preferences) {
        self.prefs = prefs
        super.init()
    }

    func settingsView() -> AnyView {
        AnyView(WindowSettingsView(prefs: prefs))
    }

    func installHotKeys(into center: HotKeyCenter) {
        guard prefs.windowShortcutsEnabled else { return }
        for shortcut in WindowShortcut.all {
            center.register(shortcut.key, modifiers: shortcut.carbonModifiers) { [weak self] in
                self?.windows.perform(shortcut.action)
            }
        }
    }

    func menuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for (index, group) in WindowShortcut.groups.enumerated() {
            if index > 0 { items.append(.separator()) }
            for shortcut in group.shortcuts {
                let item = NSMenuItem(
                    title: shortcut.action.title,
                    action: #selector(moveWindow(_:)),
                    keyEquivalent: prefs.windowShortcutsEnabled ? shortcut.keyEquivalent : ""
                )
                item.keyEquivalentModifierMask = shortcut.modifierFlags
                item.representedObject = shortcut.action.rawValue
                item.target = self
                items.append(item)
            }
        }
        return items
    }

    @objc private func moveWindow(_ sender: NSMenuItem) {
        guard let action = (sender.representedObject as? String).flatMap(WindowAction.init(rawValue:)) else { return }
        windows.perform(action)
    }
}

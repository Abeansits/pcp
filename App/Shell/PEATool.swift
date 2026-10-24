import AppKit
import SwiftUI

@MainActor
protocol PEATool: AnyObject {
    var id: String { get }
    var title: String { get }
    /// SF Symbol name on the Settings toolbar tab.
    var settingsSymbol: String { get }
    /// Non-nil: this tool's items go in a status-menu submenu with this title.
    /// Nil: the items sit on the root status menu.
    var statusMenuTitle: String? { get }
    func settingsView() -> AnyView
    /// Register this tool's Carbon hot keys. Register nothing when its own shortcut switch is off.
    /// Must not call `HotKeyCenter.unregisterAll()`.
    func installHotKeys(into center: HotKeyCenter)
    /// Items for the status menu. The tool sets `target` on each actionable item.
    /// Rebuild every call; do not cache them.
    func menuItems() -> [NSMenuItem]
}

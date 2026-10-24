import AppKit
import SwiftUI

/// Settings, one toolbar tab per tool, then General.
@MainActor
enum SettingsWindow {
    static func make(tools: [any PEATool]) -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for tool in tools {
            tabs.addTabViewItem(tab(tool.title, symbol: tool.settingsSymbol, tool.settingsView()))
        }
        tabs.addTabViewItem(tab("General", symbol: "gearshape", GeneralSettingsView()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private static func tab(_ label: String, symbol: String, _ view: some View) -> NSTabViewItem {
        let host = NSHostingController(rootView: view)
        // The window takes each tab's size when you switch to it.
        host.sizingOptions = .preferredContentSize
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

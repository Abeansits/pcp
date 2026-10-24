import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let host = PEAHost()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        host.appDelegate = self
        setUpStatusItem()
        host.clipboard.onStatusChange = { [weak self] in self?.applyStatusAppearance() }
        host.start()
        NSApp.registerForRemoteNotifications() // lets iCloud push changes to us
    }

    func applicationWillTerminate(_ notification: Notification) {
        host.prepareForTermination()
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        host.handleRemoteNotification()
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow.make(tools: host.tools)
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func quit() { NSApp.terminate(nil) }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "PEA")
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = host
        item.menu = menu
        statusItem = item
    }

    private func applyStatusAppearance() {
        let appearance = host.clipboard.statusAppearance()
        statusItem?.button?.title = appearance.title
        statusItem?.button?.toolTip = appearance.toolTip
        statusItem?.button?.appearsDisabled = appearance.appearsDisabled
    }
}

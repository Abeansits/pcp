import AppKit
import Carbon.HIToolbox
import Combine
import PCPCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Preferences.shared
    private lazy var model = HistoryModel(prefs: prefs)
    private lazy var sync = CloudSync(model: model)
    private lazy var panel = StackPanelController(model: model) { [weak self] item in
        self?.pick(item)
    }
    private let monitor = PasteboardMonitor()
    private let hotKeys = HotKeyCenter()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onDelta = { [weak self] delta in self?.sync.enqueue(delta) }

        monitor.onCopy = { [weak self] text, sourceApp in self?.handleCopy(text, from: sourceApp) }
        monitor.start()

        let commandShift = UInt32(cmdKey | shiftKey)
        hotKeys.register("c", modifiers: commandShift) { [weak self] in self?.panel.toggle() }
        hotKeys.register("v", modifiers: commandShift) { [weak self] in self?.pasteAndPop() }

        setUpStatusItem()
        observePreferences()

        NSApp.registerForRemoteNotifications() // lets iCloud push changes to us
        if prefs.syncEnabled { sync.start() }

        if !Paster.isTrusted && !prefs.didPromptForAccessibility {
            prefs.didPromptForAccessibility = true
            Paster.requestAccess()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.saveNow()
        sync.saveMetadataNow()
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        sync.syncNow()
    }

    // MARK: Actions

    private func handleCopy(_ text: String, from sourceApp: String?) {
        guard !prefs.recordingPaused else { return }
        if let sourceApp, prefs.ignoredApps.contains(sourceApp) { return }

        let isSecret = prefs.secretHandling != .off && SecretDetector.looksLikeSecret(text)
        if isSecret && prefs.secretHandling == .neverStore { return }
        model.record(
            text,
            sensitive: isSecret,
            expiresAt: isSecret ? Date().addingTimeInterval(prefs.secretTTL) : nil
        )
    }

    /// ⇧⌘V: paste the next item from the stack and remove it from the stack.
    private func pasteAndPop() {
        monitor.poll() // pick up a copy from the last half second
        guard let item = model.pop(order: prefs.pasteOrder) else {
            NSSound.beep()
            return
        }
        monitor.write(item.text, concealed: item.isSensitive)
        Paster.paste()
    }

    /// An item was chosen in the history panel.
    private func pick(_ item: ClipItem) {
        model.use(item.id)
        monitor.write(item.text, concealed: item.isSensitive)
        guard prefs.pasteOnSelect else { return }
        // Give the previous app a moment to get keyboard focus back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Paster.paste()
        }
    }

    @objc private func showHistory() { panel.show() }
    @objc private func pasteNext() {
        // Let the menu close and focus return to the previous app first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.pasteAndPop() }
    }
    @objc private func togglePause() { prefs.recordingPaused.toggle() }
    @objc private func clearStack() { model.clearStack() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func confirmClearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear all clipboard history?"
        alert.informativeText = prefs.syncEnabled
            ? "This removes it from all your devices synced through iCloud."
            : "This can't be undone."
        alert.addButton(withTitle: "Clear History").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.removeAll()
        }
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(prefs: prefs, sync: sync) { [weak self] in self?.confirmClearHistory() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "PCP Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "PCP")
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        // Show how many items are waiting on the paste stack.
        model.$history
            .map(\.stack.count)
            .removeDuplicates()
            .sink { [weak self] count in
                self?.statusItem?.button?.title = count > 0 ? " \(count)" : ""
            }
            .store(in: &cancellables)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let commandShift: NSEvent.ModifierFlags = [.command, .shift]

        let show = NSMenuItem(title: "Show History", action: #selector(showHistory), keyEquivalent: "c")
        show.keyEquivalentModifierMask = commandShift
        menu.addItem(show)

        let stackCount = model.history.stack.count
        let paste = NSMenuItem(
            title: stackCount > 0 ? "Paste Next (\(stackCount) on stack)" : "Paste Next",
            action: stackCount > 0 ? #selector(pasteNext) : nil,
            keyEquivalent: "v"
        )
        paste.keyEquivalentModifierMask = commandShift
        menu.addItem(paste)
        menu.addItem(NSMenuItem(
            title: "Clear Stack", action: stackCount > 0 ? #selector(clearStack) : nil, keyEquivalent: ""
        ))

        menu.addItem(.separator())
        let pause = NSMenuItem(title: "Pause Recording", action: #selector(togglePause), keyEquivalent: "")
        pause.state = prefs.recordingPaused ? .on : .off
        menu.addItem(pause)
        menu.addItem(NSMenuItem(title: "Clear History…", action: #selector(confirmClearHistory), keyEquivalent: ""))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit PCP", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil { item.target = self }
    }

    // MARK: Preferences

    private func observePreferences() {
        prefs.$syncEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                enabled ? self?.sync.start() : self?.sync.stop()
            }
            .store(in: &cancellables)

        prefs.$historyLimit
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] limit in self?.model.setCapacity(limit) }
            .store(in: &cancellables)

        prefs.$forgetAfterDays
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.model.purgeExpired() }
            }
            .store(in: &cancellables)

        prefs.$recordingPaused
            .sink { [weak self] paused in
                self?.statusItem?.button?.appearsDisabled = paused
            }
            .store(in: &cancellables)
    }
}

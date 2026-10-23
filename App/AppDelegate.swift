import AppKit
import Carbon.HIToolbox
import Combine
import PEACore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Preferences.shared
    private lazy var model = HistoryModel(prefs: prefs)
    private lazy var sync = CloudSync(model: model)
    private lazy var panel = StackPanelController(model: model, prefs: prefs) { [weak self] item, rich in
        self?.pick(item, rich: rich)
    }
    private let monitor = PasteboardMonitor()
    private let hotKeys = HotKeyCenter()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onDelta = { [weak self] delta in self?.sync.enqueue(delta) }

        monitor.onCopy = { [weak self] capture, sourceApp in self?.handleCopy(capture, from: sourceApp) }
        monitor.start()
        bindHotKeys()

        setUpStatusItem()
        observePreferences()

        NSApp.registerForRemoteNotifications() // lets iCloud push changes to us
        if prefs.syncEnabled { sync.start() }

        if !Paster.canPostEvents && !prefs.didPromptForAccessibility {
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

    private func handleCopy(_ capture: ClipboardCapture, from sourceApp: String?) {
        guard !prefs.recordingPaused else { return }
        if let sourceApp, prefs.ignoredApps.contains(sourceApp) { return }

        let isSecret = prefs.secretHandling != .off && SecretDetector.looksLikeSecret(capture.text)
        if isSecret && prefs.secretHandling == .neverStore { return }
        model.record(
            capture.text,
            html: isSecret ? nil : capture.html,
            rtf: isSecret ? nil : capture.rtf,
            sensitive: isSecret,
            expiresAt: isSecret ? Date().addingTimeInterval(prefs.secretTTL) : nil
        )
    }

    /// Paste the next stack item and remove it from the stack.
    /// `rich` also puts the stored HTML or RTF on the pasteboard.
    private func pasteAndPop(rich: Bool = false) {
        monitor.poll() // pick up a copy from the last half second
        guard let item = model.pop(order: prefs.pasteOrder) else {
            NSSound.beep()
            return
        }
        monitor.write(item, rich: rich)
        Paster.paste()
    }

    /// An item was chosen in the history panel. Only that item leaves the stack.
    private func pick(_ item: ClipItem, rich: Bool) {
        model.use(item.id)
        monitor.write(item, rich: rich)
        guard prefs.pasteOnSelect else { return }
        // Give the previous app a moment to get keyboard focus back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Paster.paste()
        }
    }

    private func bindHotKeys() {
        guard !prefs.isCapturingShortcut else {
            hotKeys.unregisterAll()
            return
        }
        hotKeys.unregisterAll()
        let show = prefs.historyShortcut
        let paste = prefs.pasteShortcut
        hotKeys.register(show.character, modifiers: show.carbonModifiers) { [weak self] in self?.panel.toggle() }
        hotKeys.register(paste.character, modifiers: paste.carbonModifiers) { [weak self] in self?.pasteAndPop() }
        // ⌥ added to the paste shortcut pastes formatting, when the clip has any.
        let styled = paste.addingOption()
        if styled != paste {
            hotKeys.register(styled.character, modifiers: styled.carbonModifiers) { [weak self] in
                self?.pasteAndPop(rich: true)
            }
        }
    }

    @objc private func showHistory() { panel.show() }
    @objc private func pasteNext() {
        // Let the menu close and focus return to the previous app first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.pasteAndPop() }
    }
    @objc private func pasteNextStyled() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.pasteAndPop(rich: true) }
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
            window.title = "PEA Settings"
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
        item.button?.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "PEA")
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        model.$history
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        updateStatusItem()
    }

    private func updateStatusItem() {
        let count = model.history.stack.count
        statusItem?.button?.title = count > 0 ? " \(count)" : ""
        if let next = model.history.peek(order: prefs.pasteOrder) {
            statusItem?.button?.toolTip = "Next: \(next.preview(maxLength: 80))"
        } else {
            statusItem?.button?.toolTip = "Nothing waiting to paste"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let showShortcut = prefs.historyShortcut
        let pasteShortcut = prefs.pasteShortcut

        let show = NSMenuItem(title: "Show History", action: #selector(showHistory), keyEquivalent: showShortcut.key)
        show.keyEquivalentModifierMask = showShortcut.modifierFlags
        menu.addItem(show)

        let stackCount = model.history.stack.count
        let next = model.history.peek(order: prefs.pasteOrder)
        let pasteTitle: String
        if let next {
            pasteTitle = "Paste Next: \(next.preview(maxLength: 48))"
        } else {
            pasteTitle = "Paste Next"
        }
        let paste = NSMenuItem(
            title: pasteTitle,
            action: stackCount > 0 ? #selector(pasteNext) : nil,
            keyEquivalent: pasteShortcut.key
        )
        paste.keyEquivalentModifierMask = pasteShortcut.modifierFlags
        menu.addItem(paste)
        if stackCount > 0, next?.hasRichText == true, pasteShortcut.addingOption() != pasteShortcut {
            let styled = NSMenuItem(
                title: "Paste Next with Style",
                action: #selector(pasteNextStyled),
                keyEquivalent: pasteShortcut.key
            )
            styled.keyEquivalentModifierMask = pasteShortcut.addingOption().modifierFlags
            menu.addItem(styled)
        }
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
        menu.addItem(NSMenuItem(title: "Quit PEA", action: #selector(quit), keyEquivalent: "q"))

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

        prefs.$pasteOrder
            .dropFirst()
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        Publishers.Merge3(
            prefs.$historyShortcut.dropFirst().map { _ in () },
            prefs.$pasteShortcut.dropFirst().map { _ in () },
            prefs.$isCapturingShortcut.dropFirst().map { _ in () }
        )
        .sink { [weak self] in self?.bindHotKeys() }
        .store(in: &cancellables)
    }
}

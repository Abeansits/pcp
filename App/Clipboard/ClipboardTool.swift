import AppKit
import Combine
import PEACore
import SwiftUI

@MainActor
final class ClipboardTool: NSObject, PEATool {
    let id = "clipboard"
    let title = "Clipboard"
    let settingsSymbol = "doc.on.clipboard"
    let statusMenuTitle: String? = nil

    var onStatusChange: (() -> Void)?

    private let prefs: Preferences
    private let model: HistoryModel
    private let sync: CloudSync
    private let monitor = PasteboardMonitor()
    private lazy var panel = StackPanelController(model: model, prefs: prefs) { [weak self] item, rich in
        self?.pick(item, rich: rich)
    }
    private var cancellables: Set<AnyCancellable> = []

    init(prefs: Preferences) {
        self.prefs = prefs
        let model = HistoryModel(prefs: prefs)
        self.model = model
        self.sync = CloudSync(model: model)
        super.init()
    }

    func settingsView() -> AnyView {
        AnyView(ClipboardSettingsView(prefs: prefs, sync: sync) { [weak self] in
            self?.confirmClearHistory()
        })
    }

    func installHotKeys(into center: HotKeyCenter) {
        guard prefs.clipboardShortcutsEnabled else { return }
        let show = prefs.historyShortcut
        let paste = prefs.pasteShortcut
        center.register(show.character, modifiers: show.carbonModifiers) { [weak self] in self?.panel.toggle() }
        center.register(paste.character, modifiers: paste.carbonModifiers) { [weak self] in self?.pasteAndPop() }
        // ⌥ added to the paste shortcut pastes formatting, when the clip has any.
        let styled = paste.addingOption()
        if styled != paste {
            center.register(styled.character, modifiers: styled.carbonModifiers) { [weak self] in
                self?.pasteAndPop(rich: true)
            }
        }
    }

    func menuItems() -> [NSMenuItem] {
        let shortcutsOn = prefs.clipboardShortcutsEnabled
        let showShortcut = prefs.historyShortcut
        let pasteShortcut = prefs.pasteShortcut
        var items: [NSMenuItem] = []

        let show = NSMenuItem(
            title: "Show History",
            action: #selector(showHistory),
            keyEquivalent: shortcutsOn ? showShortcut.key : ""
        )
        show.keyEquivalentModifierMask = showShortcut.modifierFlags
        show.target = self
        items.append(show)

        let stackCount = model.history.stack.count
        let next = model.history.peek(order: prefs.pasteOrder)
        let pasteTitle = next.map { "Paste Next: \($0.preview(maxLength: 48))" } ?? "Paste Next"
        let paste = NSMenuItem(
            title: pasteTitle,
            action: stackCount > 0 ? #selector(pasteNext) : nil,
            keyEquivalent: shortcutsOn ? pasteShortcut.key : ""
        )
        paste.keyEquivalentModifierMask = pasteShortcut.modifierFlags
        paste.target = self
        items.append(paste)
        if stackCount > 0, next?.hasRichText == true, pasteShortcut.addingOption() != pasteShortcut {
            let styledShortcut = pasteShortcut.addingOption()
            let styled = NSMenuItem(
                title: "Paste Next with Style",
                action: #selector(pasteNextStyled),
                keyEquivalent: shortcutsOn ? pasteShortcut.key : ""
            )
            styled.keyEquivalentModifierMask = styledShortcut.modifierFlags
            styled.target = self
            items.append(styled)
        }
        let clear = NSMenuItem(
            title: "Clear Stack",
            action: stackCount > 0 ? #selector(clearStack) : nil,
            keyEquivalent: ""
        )
        clear.target = self
        items.append(clear)

        items.append(.separator())
        let pause = NSMenuItem(title: "Pause Recording", action: #selector(togglePause), keyEquivalent: "")
        pause.state = prefs.recordingPaused ? .on : .off
        pause.target = self
        items.append(pause)
        let clearHistory = NSMenuItem(title: "Clear History…", action: #selector(confirmClearHistory), keyEquivalent: "")
        clearHistory.target = self
        items.append(clearHistory)
        return items
    }

    func statusAppearance() -> (title: String, toolTip: String, appearsDisabled: Bool) {
        let count = model.history.stack.count
        let title = count > 0 ? " \(count)" : ""
        let toolTip: String
        if let next = model.history.peek(order: prefs.pasteOrder) {
            toolTip = "Next: \(next.preview(maxLength: 80))"
        } else {
            toolTip = "Nothing waiting to paste"
        }
        return (title, toolTip, prefs.recordingPaused)
    }

    func start() {
        model.onDelta = { [weak self] delta in self?.sync.enqueue(delta) }
        monitor.onCopy = { [weak self] capture, sourceApp in self?.handleCopy(capture, from: sourceApp) }
        monitor.start()
        if prefs.syncEnabled { sync.start() }

        if !Paster.canPostEvents && !prefs.didPromptForAccessibility {
            prefs.didPromptForAccessibility = true
            Paster.requestAccess()
        }
        observePreferences()
    }

    func prepareForTermination() {
        model.saveNow()
        sync.saveMetadataNow()
    }

    func handleRemoteNotification() {
        sync.syncNow()
    }

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

        model.$history
            .sink { [weak self] _ in self?.onStatusChange?() }
            .store(in: &cancellables)
        prefs.$pasteOrder
            .sink { [weak self] _ in self?.onStatusChange?() }
            .store(in: &cancellables)
        prefs.$recordingPaused
            .sink { [weak self] _ in self?.onStatusChange?() }
            .store(in: &cancellables)
    }
}

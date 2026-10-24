import AppKit
import Combine

@MainActor
final class PEAHost: NSObject, NSMenuDelegate {
    let clipboard: ClipboardTool
    let windows: WindowTool
    let tools: [any PEATool]
    let hotKeys = HotKeyCenter()

    private let prefs: Preferences
    private var cancellables: Set<AnyCancellable> = []
    weak var appDelegate: AppDelegate?

    override init() {
        let prefs = Preferences.shared
        self.prefs = prefs
        let clipboard = ClipboardTool(prefs: prefs)
        let windows = WindowTool(prefs: prefs)
        self.clipboard = clipboard
        self.windows = windows
        self.tools = [clipboard, windows]
        super.init()
    }

    func start() {
        clipboard.start()
        bindHotKeys()
        observePreferences()
    }

    func prepareForTermination() {
        clipboard.prepareForTermination()
    }

    func handleRemoteNotification() {
        clipboard.handleRemoteNotification()
    }

    /// Clipboard is installed first, so a clipboard shortcut left on the same
    /// keys as a window shortcut still wins.
    private func bindHotKeys() {
        hotKeys.unregisterAll()
        guard !prefs.isCapturingShortcut else { return }
        clipboard.installHotKeys(into: hotKeys)
        windows.installHotKeys(into: hotKeys)
    }

    private func observePreferences() {
        // @Published fires before the new value is stored; read it on the next turn.
        Publishers.Merge(
            prefs.objectWillChange.map { _ in () },
            prefs.$isCapturingShortcut.dropFirst().map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.bindHotKeys() }
        .store(in: &cancellables)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for tool in tools where tool.statusMenuTitle == nil {
            for item in tool.menuItems() {
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        for tool in tools {
            guard let title = tool.statusMenuTitle else { continue }
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for item in tool.menuItems() {
                submenu.addItem(item)
            }
            parent.submenu = submenu
            menu.addItem(parent)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.showSettings), keyEquivalent: ",")
        settings.target = appDelegate
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit PEA", action: #selector(AppDelegate.quit), keyEquivalent: "q")
        quit.target = appDelegate
        menu.addItem(quit)
    }
}

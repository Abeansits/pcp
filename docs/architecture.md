# PEA architecture

This is the contract for the in-process shell. The host currently ships two tools. Adding another one follows [the roadmap](ROADMAP.md#adding-a-tool).

PEA is one AppKit process. `main.swift` sets `NSApplication` activation policy `.accessory` (menu bar only, no Dock icon), installs `AppDelegate`, and turns `SIGTERM` into `NSApp.terminate(nil)` so a quit from `make install` still runs `applicationWillTerminate`. Tools are types in that process. They are not plugins, bundles, XPC services, or scripts.

## Public identity

The GitHub repository stays `Abeansits/pcp`. Do not rename it, and do not edit the GitHub description. The product, the menu-bar app, the Xcode target, and `PRODUCT_NAME` are PEA. The Swift package is `PEACore`. XcodeGen writes `PEA.xcodeproj`, which `.gitignore` already ignores.

The string PCP stays only for the migration in [PCP migration](#pcp-migration). That is the only reason to keep it.

## Shipped tools

The host's tool list is exactly this, in this order:

1. Clipboard
2. Windows

Clipboard is the shipped PCP replacement (history, paste stack, secret filtering, iCloud). Windows is the shipped Magnet-style mover. Text actions (the PopClip-shaped tool) stay "Next, not started" in `docs/ROADMAP.md`. It has no folder, type, settings tab, or menu yet.

## `PEATool`

`App/Shell/PEATool.swift`. One `@MainActor` protocol, `PEATool: AnyObject`. No associated types. The host stores `[any PEATool]`.

```swift
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
```

Nothing else goes on the protocol. Startup, quit, remote notifications, and the status-item text are clipboard work. The host calls them on the concrete `ClipboardTool`, not through `PEATool`.

| Tool | Type | `id` | `title` | `settingsSymbol` | `statusMenuTitle` |
|---|---|---|---|---|---|
| Clipboard | `ClipboardTool` | `clipboard` | `Clipboard` | `doc.on.clipboard` | `nil` |
| Windows | `WindowTool` | `windows` | `Windows` | `rectangle.split.2x1` | `Move Window` |

Both are `@MainActor final class …: NSObject, PEATool`, so they can be `NSMenuItem` targets. They live in the app target, not in `PEACore`.

## `PEAHost`

`App/Shell/PEAHost.swift`. `@MainActor final class PEAHost: NSObject, NSMenuDelegate`.

The host owns the tool list. It creates both tools with `Preferences.shared` (the type's `init` is private; do not construct another `Preferences`):

```swift
let clipboard: ClipboardTool
let windows: WindowTool
let tools: [any PEATool]   // [clipboard, windows]
let hotKeys = HotKeyCenter()
```

`tools` is that array literal. Do not sort it, do not load it from a plist, and do not discover tools by scanning the bundle.

`AppDelegate` owns the process: the status item, application lifecycle, and this host. It does not construct window actions or paste commands. It does not reference `HistoryModel`, `CloudSync`, `PasteboardMonitor`, `StackPanelController`, `Paster`, `WindowManager`, `WindowAction`, or `WindowShortcut`.

What the host does:

- `start()` calls `clipboard.start()`, then `bindHotKeys()`, then starts observing preferences.
- `prepareForTermination()` calls `clipboard.prepareForTermination()` only. Windows has nothing to save.
- `handleRemoteNotification()` calls `clipboard.handleRemoteNotification()` only.
- `bindHotKeys()` is the only caller of `hotKeys.unregisterAll()`. If `prefs.isCapturingShortcut` is true, it returns after that. Otherwise it calls `clipboard.installHotKeys(into:)` and then `windows.installHotKeys(into:)`.
- `menuNeedsUpdate(_:)` rebuilds the status menu. `AppDelegate` sets the status item's menu delegate to the host.

`HotKeyCenter.unregisterAll()` does not reset `nextID`. `reregisterAll()` installs in sorted id order, so the first `register` after each `unregisterAll` keeps the lower id. Carbon `RegisterEventHotKey` gives the first registration the key. Clipboard is installed first for that reason: a clipboard shortcut left on the same keys as a window shortcut still wins. Tools register only their own keys.

Rebind on the next main-queue turn after `Preferences.objectWillChange` or `prefs.$isCapturingShortcut`, same reason as today's `AppDelegate`: `@Published` fires before the new value is stored. `receive(on: RunLoop.main)`, then `bindHotKeys()`. `ShortcutField` in `App/Shortcut.swift` sets `isCapturingShortcut`. While it is true, every global shortcut, including Windows, stays unregistered. That matches the current behavior.

## Status menu

`menuNeedsUpdate` builds this, top to bottom:

1. Every tool whose `statusMenuTitle` is nil, in tool-list order. Today that is only Clipboard: append `clipboard.menuItems()` directly, including the separator the tool returns.
2. A separator.
3. Every tool whose `statusMenuTitle` is non-nil, in tool-list order. The parent item's title is `statusMenuTitle`, its action is nil, and its submenu is that tool's `menuItems()`.
4. A separator.
5. `Settings…` (`keyEquivalent` `","`, target `AppDelegate`) and `Quit PEA` (`keyEquivalent` `"q"`, target `AppDelegate`).

The host does not retarget tool items. Separators stay separators.

Clipboard's `menuItems()`, same actions as `AppDelegate.menuNeedsUpdate` today:

| Item | Action | Enabled when | Key equivalent |
|---|---|---|---|
| Show History | `StackPanelController.show()` (not `toggle`) | always | `historyShortcut` |
| Paste Next | `pasteAndPop()` after 0.15 s | stack is non-empty; title uses `preview(maxLength: 48)` when there is a next item | `pasteShortcut` |
| Paste Next with Style | `pasteAndPop(rich: true)` after 0.15 s | stack non-empty, next item `hasRichText`, and `pasteShortcut.addingOption() != pasteShortcut` | `pasteShortcut.addingOption()` |
| Clear Stack | `model.clearStack()` | stack non-empty | none |
| separator | | | |
| Pause Recording | `recordingPaused.toggle()`, checkmark follows the flag | always | none |
| Clear History… | the existing `NSAlert` (iCloud wording when `syncEnabled`) | always | none |

The hotkey for show-history still calls `StackPanelController.toggle()`. The menu item still calls `show()`. The 0.15 s menu delay and the 0.05 s history-panel delay stay.

When `clipboardShortcutsEnabled` is false, those three items stay in the menu and keep their actions. Their `keyEquivalent` is `""`. Still assign `keyEquivalentModifierMask` from the shortcut, which is what `windowMenu()` does today when window shortcuts are off.

Windows' `menuItems()` is today's `windowMenu()` body: `WindowShortcut.groups` in order, a separator between groups, `representedObject` = `action.rawValue`, action calls `WindowManager.perform`. `keyEquivalent` is `shortcut.keyEquivalent` when `windowShortcutsEnabled` is true and `""` otherwise.

## Status item

The status item stays the SF Symbol `paperclip`, accessibility description `PEA`, `imagePosition` `.imageLeading`. A generic template icon is not a substitute: the button title is the paste-stack count (`" \(count)"` when the stack is non-empty, otherwise `""`).

`ClipboardTool.statusAppearance()` returns the title, the tooltip, and `appearsDisabled`. Tooltip text stays `"Next: \(next.preview(maxLength: 80))"` or `"Nothing waiting to paste"`. `appearsDisabled` follows `recordingPaused`. The symbol is shell policy, not a `PEATool` property. `AppDelegate` applies the appearance to the button. `ClipboardTool.onStatusChange` fires when `HistoryModel.$history`, `pasteOrder`, or `recordingPaused` changes. `AppDelegate` sets that callback before `host.start()`.

## Lifecycle

`AppDelegate.applicationDidFinishLaunching`: create the status item, wire `onStatusChange`, call `host.start()`, then `NSApp.registerForRemoteNotifications()`. Registration stays on the delegate because it is an `NSApp` call.

`ClipboardTool.start()` does what `applicationDidFinishLaunching` does for the clipboard today:

- `model.onDelta` enqueues into `CloudSync`.
- `PasteboardMonitor.onCopy` records through the same `handleCopy` rules (`recordingPaused`, `ignoredApps`, `SecretDetector`, `secretHandling`, `secretTTL`).
- `monitor.start()`.
- If `syncEnabled`, `sync.start()`.
- If `!Paster.canPostEvents && !prefs.didPromptForAccessibility`, set the flag and call `Paster.requestAccess()`.
- Observe `syncEnabled`, `historyLimit` (drop-first, deduped, 500 ms debounce, `setCapacity`), `forgetAfterDays` (purge on the next turn), `recordingPaused`, and `pasteOrder`.

`applicationWillTerminate` calls `host.prepareForTermination()`, which calls `model.saveNow()` and then `sync.saveMetadataNow()`, in that order.

`application(_:didReceiveRemoteNotification:)` calls `host.handleRemoteNotification()`, which calls `CloudSync.syncNow()`. `syncNow()` already no-ops when the engine is nil.

The window Accessibility prompt stays inside `WindowManager.perform` (once a launch, then beep). Do not prompt for it at launch.

## Settings

The settings window is the toolbar-tab window in `App/Shell/SettingsWindow.swift`.

```swift
enum SettingsWindow {
    static func make(tools: [any PEATool]) -> NSWindow
}
```

Same window as today: `NSTabViewController` with `tabStyle` `.toolbar`, `styleMask` `[.titled, .closable]`, `toolbarStyle` `.preference`, `isReleasedWhenClosed` false, centered. Each tab is an `NSHostingController` with `sizingOptions` `.preferredContentSize`, the tool's `title`, and `NSImage(systemSymbolName: tool.settingsSymbol)`.

Tab order is `tools`, then General. General is not a `PEATool`. Its symbol is `gearshape`, its label is `General`, and its view is `GeneralSettingsView` in `App/Shell/GeneralSettingsView.swift` (launch at login via `SMAppService.mainApp`, and the About block that reads `CFBundleShortVersionString`).

`AppDelegate` holds the `NSWindow?` and builds it lazily with `SettingsWindow.make(tools: host.tools)`. It does not construct a clipboard or windows view itself.

`ClipboardSettingsView` and the private `IgnoredAppsEditor` live in `App/Clipboard/ClipboardSettingsView.swift`. The tool's `settingsView()` returns `AnyView` of that view, observing `Preferences` and `CloudSync`, with the clear-history alert invoked through a closure the tool supplies.

The Clipboard Shortcuts section starts with:

```swift
Toggle("Clipboard shortcuts", isOn: $prefs.clipboardShortcutsEnabled)
```

One footer sentence: the menu bar's history and paste items work with the shortcuts off. Pause recording stays in the History section. It is not this switch.

`WindowSettingsView` stays in `App/Windows/WindowSettingsView.swift`. `WindowTool.settingsView()` wraps it.

## Preferences

`App/Preferences.swift` stays the only `ObservableObject` and the only `UserDefaults` facade. Tools add keys there. Do not split defaults across files, and do not give a tool its own `UserDefaults` suite.

Add `clipboardShortcutsEnabled`, parallel to `windowShortcutsEnabled`:

- `Key.clipboardShortcutsEnabled = "clipboardShortcutsEnabled"`
- `@Published var clipboardShortcutsEnabled: Bool`, `didSet` writes the bool
- `defaults.register` default `true`
- Read it in `init` with `defaults.bool(forKey:)`

Existing domains lack the key, so `register` makes the default `true` and current shortcuts keep working. Do not reuse `recordingPaused`. Do not change the `windowShortcutsEnabled` key or any other key. `importPCPSettings` stays in `Preferences.init`.

## Hot keys per tool

`ClipboardTool.installHotKeys` returns immediately when `clipboardShortcutsEnabled` is false. Otherwise it registers, in this order, the same three keys `bindHotKeys` registers today:

1. `historyShortcut` → `panel.toggle()`
2. `pasteShortcut` → `pasteAndPop()`
3. `pasteShortcut.addingOption()`, only when that differs from `pasteShortcut` → `pasteAndPop(rich: true)`

`WindowTool.installHotKeys` returns immediately when `windowShortcutsEnabled` is false. Otherwise it registers `WindowShortcut.all` in order, each calling `windows.perform(shortcut.action)`.

`HotKeyCenter`, `HotKey`, and `KeyboardLayout` stay in `App/HotKeys.swift`. `AppShortcut` and `ShortcutField` stay in `App/Shortcut.swift`.

## Clipboard and Windows code

`ClipboardTool` owns `HistoryModel`, `CloudSync`, `PasteboardMonitor`, `StackPanelController`, and every paste path (`handleCopy`, `pasteAndPop`, `pick`). Those types stay in `App/Clipboard/` and keep their current behavior. `HistoryModel.supportDirectory` still moves `~/Library/Application Support/PCP` to `PEA` once.

`WindowTool` owns `WindowManager` and the menu actions. `WindowManager`, `WindowShortcuts`, and `WindowSettingsView` stay where they are.

## Two-line history list preview

`ClipItem.listPreview` is in `Core/Sources/PEACore/ClipItem.swift`. `testListPreviewKeepsTwoLines` covers it. `Row` in `App/Clipboard/StackPanel.swift` draws it.

`ClipItem.listPreview(maxLines: Int = 2) -> String`:

- A sensitive item returns `preview()` and does not show its text.
- Normalize line breaks before splitting: replace `\r\n` with `\n`, then `\r` with `\n`, then U+2028 and U+2029 with `\n`. Do it in that order.
- Split on `\n`, keeping empty subsequences. Each piece: tabs become spaces, then trim `.whitespaces`. Drop empty pieces.
- Keep at most `maxLines` pieces. A further non-empty piece does not become a third line. Append `…` (U+2026, not three periods) to the last kept line.
- Join kept lines with `\n`. If none remain, return `preview()`.
- This is display-only. Do not rewrite `text`.

Change `preview`'s comment from list rows to the menu and tooltip. The status item and Paste Next keep calling `preview`. They do not call `listPreview`.

`Row` in `StackPanel.swift` draws every item, sensitive or not, from `listPreview()`. Split that string on `\n` and put each piece in its own `Text` with `lineLimit(1)` and `truncationMode(.tail)`. The column frame is `minWidth: 0`, `maxWidth: .infinity`, `alignment: .leading`. Do not use one `Text` with `lineLimit(2)` or `fixedSize`: that sizes the row to the unwrapped string, then the wrapped lines paint over the next row.

Add `testListPreviewKeepsTwoLines` next to `testPreviewCollapsesWhitespaceAndMasksSecrets`, which stays:

- `"  hello\n\n  world\t!  "` → `"hello\nworld !"`
- `"a\r\nb\rc"` → `"a\nb…"`
- `"only"` → `"only"`
- sensitive `"secret\nline"` equals that item's `preview()`

## Version

In `project.yml`, set `MARKETING_VERSION` to `1.1.0` and `CURRENT_PROJECT_VERSION` to `4`. `Config/Info.plist` already reads `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`. Do not hard-code them there.

1.1.0 is the shell plus the clipboard shortcut switch. The list-preview port ships in the same version because the stash has to land here. Do not open a second version for it. `project.yml` `sources` is already the whole `App` directory, so `App/Shell/` needs no new source entry. Do not add a target.

## PCP migration

These are the only PCP mentions that stay. Do not delete them while renaming, and do not add new ones.

| Site | What it does |
|---|---|
| `HistoryModel.supportDirectory` | If `Application Support/PEA` is missing and `Application Support/PCP` exists, move the old folder. |
| `Preferences.importPCPSettings` | On first launch under bundle id `com.example.pea`, copy the `com.example.pcp` persistent domain when the new domain is empty. |
| `Makefile` `install` | Warn when `$(PREFIX)/PCP.app` exists, and when a process named `PCP` is still running. Do not launch PEA in that second case. |
| `README.md` "Coming from PCP", `docs/ROADMAP.md` "Replaces PCP" | User-facing rename notes. |

`scripts/check-names.sh` fails the build on these four contiguous needles, in any other file:

- `PCPCore`
- `PCP.xcodeproj`
- `Personal Copy Paste`
- `PRODUCT_NAME` set to `PCP` (`PRODUCT_NAME: PCP` in `project.yml`, or `PRODUCT_NAME = PCP` in a project file)

The script excludes itself and this file (`docs/architecture.md`), plus `.git/`, `build/`, `Core/.build/`, `Core/.swiftpm/`, `DerivedData/`, `output/`, and `xcuserdata/`. It checks both paths and file contents, including untracked files, so a leftover `PCP.xcodeproj` directory fails. Migration lines that only say PCP, `com.example.pcp`, or `PCP.app` do not match the needles and do not need an allowlist. A migration comment that grows one of the four needles fails.

XcodeGen's output is `PEA.xcodeproj`, which `.gitignore` ignores. Do not generate or keep a `PCP.xcodeproj`, and do not commit either project.

## CI and local proof

`.github/workflows/ci.yml` already has one job, `build`, on `macos-15`:

1. `cd Core && swift test`
2. `brew install xcodegen && xcodegen generate`
3. Unsigned Debug `xcodebuild` of `PEA.xcodeproj` / scheme `PEA`, `-derivedDataPath build`, `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGN_ENTITLEMENTS=` empty
4. `make install PREFIX="$RUNNER_TEMP/Applications" OPEN=0`

Keep those four steps. Insert `bash scripts/check-names.sh` immediately after checkout.

Add a second job, `core-linux`, `runs-on: ubuntu-latest`. It checks out, runs `swift-actions/setup-swift@v2` with `swift-version: "6.0"`, then `cd Core && swift test`. It does not install XcodeGen and it does not build the app. The job exists so `PEACore` stays free of AppKit, UIKit, and CloudKit. `Core/Package.swift` stays `swift-tools-version:5.9` and `platforms: [.macOS(.v14)]`. Do not bump the tools version to turn on the Swift 6 language mode. Swift 6.0 is the toolchain. If that job fails on a Core concurrency error, fix it in `Core/` without an AppKit import. Do not drop the job.

`WindowLayout.swift` keeps its `canImport(CoreGraphics)` branch so Linux Foundation still builds.

Local proof is `make test`, then `xcodegen generate`, then an unsigned Debug build:

```sh
make test
xcodegen generate
xcodebuild -project PEA.xcodeproj -scheme PEA -configuration Debug \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_ENTITLEMENTS= build
```

`make install` quits a running PEA and replaces `~/Applications/PEA.app`. `make unsigned` is a Release build. Neither is the local proof. CI runs `make install` in a scratch prefix.

## Docs that must match

Replace the parenthetical in `docs/ROADMAP.md` under "Off means off". It currently says clipboard can only pause recording. The line should say that a tool that is switched off registers no shortcuts, that the menu items still run, and that Clipboard's shortcut switch is separate from Pause recording. Leave tool 3 as "Next, not started".

In `README.md`, state that Settings → Clipboard can switch the clipboard shortcuts off, that Show History, Paste Next, and Paste Next with Style stay in the menu and hide their key equivalents while that switch is off, and that Pause recording is a different switch. Add `App/Shell/` to the layout tree (protocol, host, General settings). Do not rewrite the rest of the README.

## Where the shell lives

- `App/Shell/PEATool.swift` — the protocol
- `App/Shell/PEAHost.swift` — tool list, hot keys, status menu
- `App/Shell/SettingsWindow.swift` — `make(tools:)`
- `App/Shell/GeneralSettingsView.swift`
- `App/Clipboard/ClipboardTool.swift`
- `App/Clipboard/ClipboardSettingsView.swift` — `ClipboardSettingsView` and private `IgnoredAppsEditor`
- `App/Windows/WindowTool.swift`
- `scripts/check-names.sh`

There is no `App/SettingsView.swift`. Tabs come from `SettingsWindow.make(tools:)`.

These stay at `App/`. They are shell services, not tools: `HotKeys.swift`, `Shortcut.swift`, `Preferences.swift`, `Log.swift`, `main.swift`, `AppDelegate.swift`.

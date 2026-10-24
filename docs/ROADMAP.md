# PEA roadmap

PEA (Personal Everything App) is one menu bar app holding the small Mac tools I use every day, rebuilt so they're private and have no dependencies.

## Rules for every tool

- **macOS only.** AppKit and SwiftUI, public APIs, no third-party packages.
- **One app.** One menu bar icon, one Settings window with a tab per tool.
- **Off means off.** A tool that's switched off registers no shortcuts. (Clipboard can only pause recording so far.)
- **Private.** Nothing leaves the Mac except your own iCloud sync. No analytics.
- **Tested core.** Logic that doesn't need the OS goes in `PEACore` with unit tests; `App/<Tool>/` holds the OS glue.

## Tools

| # | Tool | Replaces | Status |
|---|---|---|---|
| 1 | Clipboard | PCP (this app's old self) | Shipped |
| 2 | Windows | Magnet | v1 built, needs testing on a real Mac. [Spec](specs/windows.md) |
| 3 | Text actions | PopClip | Next, not started |

### 1. Clipboard

History, paste stack, secret filtering, iCloud sync. See the [README](../README.md#clipboard).

Next, in order:

1. **Sync without CloudKit.** CloudKit needs a paid Apple Developer membership. An optional encrypted copy of the history file in a folder you pick (iCloud Drive or any synced folder) would cover a free account.
2. **Pin a few clips** so the history limit and "forget after" can't drop them.

Left out on purpose: Universal Clipboard recording, image and file history, snippet expansion, any sync server that isn't yours.

### 2. Windows

Snap the focused window to halves, quarters, thirds or full screen from the keyboard. [Spec](specs/windows.md).

- **v1 (built):** Magnet's default shortcuts, a Move Window menu, Restore, move to next/previous display.
- **v2:** drag a window to a screen edge to snap it, with a preview; rebind each shortcut.

### 3. Text actions

Select text and get a small bar of actions next to it, like PopClip.

- **v1 idea:** start with a shortcut that opens the bar for the current selection, before any automatic pop-up. Actions: copy, paste over the selection, search the web, open as a link, push to the PEA paste stack, change case, count words.
- **Hard part:** reading the selection. Accessibility's `AXSelectedText` works in native apps but not in many browsers and Electron apps. The fallback is a synthetic ⌘C, which must not end up in clipboard history.
- **v2:** show the bar automatically after a mouse selection.

## Adding a tool

1. Write a short spec in `docs/specs/<tool>.md`: goal, non-goals, shortcuts, permissions, test plan.
2. Put the pure logic in `Core/Sources/PEACore/` with tests.
3. Put the OS code in `App/<Tool>/`, a Settings tab in `SettingsWindow`, and a submenu in the menu bar menu.
4. Give it an on/off switch in `Preferences`.
5. Add it to this table and to the README.

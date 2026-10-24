# Windows: a small Magnet

Status: v1 built. Not yet tried on a real Mac.

## Goal

Move the focused window into a half, quarter, third or the whole screen with one shortcut, the way Magnet does, so a new Mac doesn't need Magnet.

## Not in v1

- Dragging a window to a screen edge to snap it.
- Changing individual shortcuts.
- Gaps between windows, animation.
- Saved layouts, per-app rules, moving windows between Spaces.

## Shortcuts

Magnet's defaults, fixed in v1. All of them can be switched off in Settings → Windows.

| Keys | Action |
|---|---|
| ⌃⌥← ⌃⌥→ ⌃⌥↑ ⌃⌥↓ | left, right, top, bottom half |
| ⌃⌥U ⌃⌥I ⌃⌥J ⌃⌥K | top-left, top-right, bottom-left, bottom-right quarter |
| ⌃⌥D ⌃⌥F ⌃⌥G | left, center, right third |
| ⌃⌥E ⌃⌥T | left, right two thirds |
| ⌃⌥↩ | maximize (fill the screen, not macOS full screen) |
| ⌃⌥C | center, keeping the size |
| ⌃⌥⌫ | restore the size and place from before the first snap |
| ⌃⌥⌘← ⌃⌥⌘→ | previous, next display |

Why not ⌘ + arrows: in every text field ⌘← and ⌘→ jump to the start and end of the line, and ⌘↑ ⌘↓ to the top and bottom. A global shortcut takes those keys away from every app.

Letters follow the keyboard layout (on Dvorak, ⌃⌥U is the key that types U), like the clipboard shortcuts. Arrows, ↩ and ⌫ are fixed keys.

## Behavior

- **Which window:** the focused window of the frontmost app. If there is none, or it's in macOS full screen, or it can't be moved, PEA beeps.
- **Which screen:** the one holding most of the window. Layouts use its visible area: the screen minus the menu bar and the Dock.
- **Edges:** splits round to whole points. Left and right half, and the three thirds, meet with no gap or overlap.
- **Windows with a minimum or fixed size** (System Settings, some dialogs) keep the size they can take and are moved as close to the target as possible without leaving the screen.
- **Same shortcut twice:** does nothing new. Cycling ½ → ⅓ → ⅔ is a v2 question.
- **Restore:** PEA remembers each window's frame from before its first snap. Snapping it again keeps that frame. Dragging the window by hand and then snapping it remembers the new place. Up to 100 windows, in memory only.
- **Displays:** ordered left to right, wrapping around. A window in one of the layouts above keeps that layout on the new screen. Any other window keeps its size (shrunk if the screen is smaller) and the relative position of its center.
- **Menu:** the menu bar menu has a Move Window submenu with every action. It works even with the shortcuts off.

## Permission

Moving another app's windows needs the Accessibility permission (`AXIsProcessTrusted`). That's a different grant from the one pasting uses (`CGPreflightPostEventAccess`), though both appear in the same Privacy & Security list. PEA asks the first time a window shortcut is used, not at launch. Settings → Windows shows the status and has an Allow… button.

## How it's built

| File | Job |
|---|---|
| `Core/Sources/PEACore/WindowLayout.swift` | Pure geometry: `WindowAction`, `ScreenRegion`, `Display`, `WindowLayout`, `RestoreFrames`. Tested in `WindowLayoutTests.swift`. |
| `App/Windows/WindowManager.swift` | Accessibility: find the focused window, read and set its frame, convert screen coordinates. |
| `App/Windows/WindowShortcuts.swift` | The shortcut table. Registered through `HotKeyCenter`, which now takes fixed key codes as well as characters. |
| `App/Windows/WindowSettingsView.swift` | The Windows tab in Settings. |

Details that matter:

- **Coordinates.** Accessibility puts (0, 0) at the top-left of the main screen with y growing down. `NSScreen` puts it at the bottom-left with y growing up. `WindowLayout.flipped` converts both ways, and all geometry in `PEACore` uses the Accessibility convention.
- **Setting a frame.** Size, then position, then size again. Setting the position first would leave a big window clamped on a smaller screen.
- **`AXEnhancedUserInterface`.** Some apps (and assistive tools) turn it on, and then every resize animates and lands in the wrong place. PEA turns it off for the move and back on afterwards.
- **Hung apps.** Accessibility calls to the frontmost app time out after 1 second instead of 6, so a frozen app can't stall PEA's main thread (which also runs the clipboard).
- **PEA's own windows** are skipped. Asking our own process for its Accessibility tree from the main thread would block.

## Test plan (on a Mac)

1. Fresh install: the first ⌃⌥← asks for Accessibility. After allowing it, ⌃⌥← snaps the window.
2. Every shortcut on a laptop screen, with the Dock at the bottom, at the left, and hidden.
3. Two displays: ⌃⌥⌘→ moves a left half to the other screen's left half; a free window keeps its size. Also with the second screen above or left of the main one.
4. Snap a window three times, then ⌃⌥⌫: it returns to where it started.
5. Apps: Finder, Safari, Chrome, an Electron app (VS Code, Slack), Terminal, System Settings (fixed width), a window in full screen (beep).
6. Switch window shortcuts off: ⌃⌥← reaches the frontmost app again, and the menu still moves windows.

## Open questions

1. Is ⌃⌥ right, or should ⌘ + arrows be an option despite the text-editing clash?
2. Should repeating a half cycle through ½, ⅓, ⅔ like Rectangle does?

## v2

- Drag to a screen edge or corner to snap, with a translucent preview.
- Rebind each shortcut. `AppShortcut` and `ShortcutField` handle characters only; they need arrow keys, ↩ and ⌫ first.
- Optional gaps between windows.

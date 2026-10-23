# PEA – Personal Everything App

Small, private Mac tools in one menu bar app. No analytics, no accounts, no in-app purchases and no third-party dependencies.

- **[Clipboard](#clipboard)**: searchable history, a copy/paste **stack**, and sync through **your own iCloud**.
- **[Windows](#windows)**: Magnet's shortcuts for snapping the focused window to halves, quarters and thirds.
- Next: text actions on a selection, like PopClip. See the [roadmap](docs/ROADMAP.md).

PEA used to be PCP, the clipboard manager alone. See [Coming from PCP](#coming-from-pcp).

## Clipboard

| Shortcut | What it does |
|---|---|
| copy (⌘C anywhere) | pushes onto the stack and into history |
| **⇧⌘C** | show history: type to search, ↑↓ to move, ↩ or **⌘1…⌘9** to paste, ⌥↩ to paste with style, ⌘⌫ to delete, esc to close |
| **⇧⌘V** | paste the next item from the stack and pop it: copy, copy, copy → paste, paste, paste |
| **⌥⇧⌘V** | same, but keep links and styling when the clip has any |

⇧⌘C and ⇧⌘V are the defaults. Change them in Settings. The menu bar paperclip shows how many items are waiting, and its tooltip names the one ⇧⌘V will paste.

### Features

- **Stack paste.** ⇧⌘V pastes in copy order (copy A B C → paste A B C); Settings can switch it to newest-first (C B A). Popping removes an item from the stack, not from history. Copying after a 15-minute pause starts a fresh stack, so ⇧⌘V never digs up something you copied hours ago. History numbers the stack in paste order. ⌥⌘↑↓ moves the selected item, ⌥⌫ takes it off the stack without deleting it, and picking one item pastes that item only.
- **History**: up to 1000 items by default, deduplicated (copying the same text again moves it to the top), searchable (every word must match, case- and accent-insensitive). You can also have items forgotten after a day, week, 30 or 90 days.
- **Password handling**:
  - Copies that password managers mark as concealed (`org.nspasteboard.ConcealedType` & friends) are **never recorded**. 1Password, Bitwarden, KeePassXC, Apple Passwords and Keychain Access do this.
  - Copies made while an app on the ignore list is frontmost are never recorded. The list is editable.
  - Text that *looks* like a password or API token (random mixed-case/digit/symbol strings, `ghp_…`, `sk-…`, `AKIA…`, JWTs, private keys) is kept **in memory only** for 60 s so ⇧⌘V still works. It is never written to disk and never synced. You can also choose "never store".
- **iCloud sync** across your Macs using the private CloudKit database. Clip text and timestamps are stored in CloudKit's `encryptedValues`, which are **end-to-end encrypted** with keys in your iCloud Keychain, so Apple can't read them. The stack is per-Mac; history is shared.
- **Links and styled text.** When a copy includes HTML or RTF, PEA keeps it. ⇧⌘V still pastes plain text. ⌥⇧⌘V, or ⌥↩ in history, pastes the formatting too. Images and files are still ignored.
- **Light on resources.** It checks the pasteboard's change counter twice a second (an integer read) and only reads contents when something changed. Global shortcuts use Carbon `RegisterEventHotKey`, which is stable, needs no permission and doesn't install a keyboard tap.
- **Few moving parts.** Only public, long-stable APIs: `NSPasteboard`, Carbon hot keys, `CGEvent`, and `CKSyncEngine`. History is a JSON file written atomically (`~/Library/Application Support/PEA/history.json`, mode 600, directory mode 700).

## Windows

Magnet's default shortcuts. They act on the focused window of the frontmost app.

| Shortcut | Puts the window |
|---|---|
| **⌃⌥← → ↑ ↓** | in the left, right, top or bottom half |
| **⌃⌥U I J K** | in the top-left, top-right, bottom-left or bottom-right quarter |
| **⌃⌥D F G** | in the left, center or right third |
| **⌃⌥E T** | in the left or right two thirds |
| **⌃⌥↩** | over the whole screen (not macOS full screen) |
| **⌃⌥C** | in the center, same size |
| **⌃⌥⌫** | back where it was before the first snap |
| **⌃⌥⌘← →** | on the previous or next display; a half stays a half |

The same actions are in the menu bar under **Move Window**, which works even with the shortcuts switched off in Settings → Windows. Layouts leave the menu bar and Dock uncovered, and halves and thirds meet without gaps. A window that can't shrink far enough (System Settings, for one) stays as close as it can without leaving the screen.

Moving another app's windows needs the **Accessibility** permission. PEA asks the first time you use a window shortcut. Settings → Windows shows whether it's allowed. The full behavior is in the [spec](docs/specs/windows.md).

## Coming from PCP

PEA is PCP renamed. On first launch it moves `~/Library/Application Support/PCP/` to `PEA/`, so your history and sync state carry over. Some things are tied to the old name or signature and need a one-time redo:

- **The old app.** Quit `PCP.app` and move it to the Trash. Two copies would both record copies. If PCP was a login item, turn **Launch at login** off in PCP first, then on in PEA.
- **Bundle id.** If `Config/Local.xcconfig` sets `PCP_BUNDLE_ID`, rename that line to `PEA_BUNDLE_ID` and keep the value. The bundle id picks the iCloud container and your settings, so keeping it keeps both. Without a Local.xcconfig the placeholder id changes from `com.example.pcp` to `com.example.pea`, and settings start from the defaults.
- **Permissions.** `make install` now signs with a new **PEA Local** certificate, so macOS asks for the paste permission once more. Remove the old PCP row in that Settings list.

## Build & install

Requirements: macOS 14+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

iCloud sync needs a **paid** Apple Developer Program membership. A free Apple ID cannot create an iCloud container. Its Personal Team profiles also expire after 7 days, and every re-sign asks for the paste permission again. For one Mac and no sync, use `make install`.

### Without iCloud

```sh
make install
```

That builds a Release app with the CloudKit entitlement left out, signs it with a certificate named **PEA Local**, and copies it to `~/Applications/PEA.app`. The first build creates the certificate in `~/Library/Keychains/pea-signing.keychain-db`. It is not an Apple certificate, so Gatekeeper will not accept it, and the first install asks for the paste permission. Later installs signed with the same certificate do not ask again. Pass `PREFIX=/Applications` if that directory is writable. Quit the running copy from the menu bar first, so the last clipboard changes are flushed, then open the installed app. Turn on **Launch at login** in its Settings only after it lives in that folder. The registration points at that path.

History is `~/Library/Application Support/PEA/history.json`. The path does not include the bundle id, so a later signed build reads the same clips. Preferences follow the bundle id. This build uses the placeholder id `com.example.pea` until you set one in `Config/Local.xcconfig`.

Deleting the PEA Local certificate, or signing with a different one, makes macOS ask for the paste permission again. That permission is in the same Privacy & Security list as Accessibility. On macOS 27 the list is named Device Control and Data Access. If paste keeps asking, remove the old PEA row and allow the current app. Run one copy. A second copy writes the same file, and the last save wins.

### GitHub release

```sh
make release NOTES="What changed."
```

That builds the same signed app, zips it, and publishes `PEA-<version>.zip` as a GitHub release. The version comes from `MARKETING_VERSION` in `project.yml`. The zip is signed with your PEA Local certificate, so it is not notarized. The release notes should say to open the app once from Finder. People who install a later release signed with that same certificate keep the paste permission.

### iCloud sync

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # set your Team ID + a unique bundle id
make open                                                # generates PEA.xcodeproj and opens it
```

In Xcode, select the **PEA** target, then **Signing & Capabilities**. Check that your team is set and that the iCloud container `iCloud.<your bundle id>` exists and is ticked (Xcode offers to create it). Then run.

On first launch:

1. **Paste keystrokes.** macOS asks to let PEA control this Mac and access your data. PEA needs that to send ⌘V into the app you're in. Without it, the text is still put on the clipboard and you press ⌘V yourself. The switch lives under Privacy & Security, in the same list as Accessibility (named Device Control and Data Access on macOS 27). A new signature can reset it. If pasting stops, remove the old PEA row and allow the current app.
2. If macOS asks whether PEA may read the clipboard, choose **Allow**. Reading the clipboard is what PEA does.
3. **Accessibility**, the first time you use a window shortcut. Window snapping needs it to move other apps' windows. It's a separate switch from paste keystrokes, in the same list.
4. Optional: enable **Launch at login** in Settings → General.

### Putting it on your other Macs

Use **Product → Archive → Distribute App → Direct Distribution**. This gives you a notarized, Developer ID–signed `PEA.app` that you copy to each Mac.

Release builds talk to the CloudKit **production** environment. Before using one, run a Debug build once and copy something so the `Clip` record type gets created. Then open [CloudKit Console](https://icloud.developer.apple.com) → your container → **Deploy Schema Changes**. You only need to do this once.

## Development

```sh
make test       # unit tests for the core logic (runs on macOS and Linux)
make build      # signed Release build (needs Config/Local.xcconfig and a paid team)
make install    # Release app in ~/Applications, signed with PEA Local, no iCloud
make release NOTES="…"  # zip that app and publish a GitHub release
```

Layout:

```
Core/           PEACore Swift package: history, stack, dedupe/merge, secret detection, search,
                persistence, window layout geometry (pure Foundation, tested)
App/            menu bar, hot keys, settings window
App/Clipboard/  pasteboard monitor, paste injection, history panel, CloudKit sync
App/Windows/    Accessibility window mover, window shortcuts, Windows settings tab
Config/         Info.plist, entitlements, signing xcconfig
docs/           roadmap and per-tool specs
```

How sync converges: each clip is a CloudKit record with a random UUID. If two Macs record the same text independently, both keep the record with the smaller UUID and delete the other, so they end up identical without coordinating. For timestamps, the newest one wins. Deletions and the history limit propagate to every device, so the smallest limit you set on any Mac applies to all of them.

## Known limits

Clipboard:

- Images and files aren't recorded. Styled text is kept and pasted only when you ask (⌥⇧⌘V or ⌥↩).
- Clips over 512 KB are skipped. Formatting larger than that is dropped, and the plain text is kept.
- Universal Clipboard (Handoff) arrivals aren't recorded, because reading them blocks while they download. Copies made on your other PEA Macs arrive through iCloud instead.
- The default shortcuts are ⇧⌘C and ⇧⌘V, which override "Paste and Match Style" and similar shortcuts in other apps. Change them in Settings.

Windows:

- The shortcuts are fixed for now; you can only switch them all off. They take ⌃⌥ + those keys from every app.
- No dragging to a screen edge to snap yet, and windows in macOS full screen are left alone.
- PEA's own windows (Settings) can't be snapped.

## Roadmap

Per tool, in [docs/ROADMAP.md](docs/ROADMAP.md). Specs for each tool are in [docs/specs](docs/specs).

## License

[MIT](LICENSE)

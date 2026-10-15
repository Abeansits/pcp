# PCP – Personal Copy Paste

A small, private clipboard manager for macOS. It lives in the menu bar, keeps a searchable clipboard history, adds a copy/paste **stack**, and syncs through **your own iCloud**. It has no analytics, no accounts, no in-app purchases and no third-party dependencies.

| Shortcut | What it does |
|---|---|
| copy (⌘C anywhere) | pushes onto the stack and into history |
| **⇧⌘C** | show history: type to search, ↑↓ to move, ↩ or **⌘1…⌘9** to paste, ⌘⌫ to delete, esc to close |
| **⇧⌘V** | paste the next item from the stack and pop it: copy, copy, copy → paste, paste, paste |

The menu bar paperclip shows how many items are waiting on the stack.

## Features

- **Stack paste.** ⇧⌘V pastes in copy order (copy A B C → paste A B C); Settings can switch it to newest-first (C B A). Popping removes an item from the stack, not from history. Copying after a 15-minute pause starts a fresh stack, so ⇧⌘V never digs up something you copied hours ago.
- **History**: up to 1000 items by default, deduplicated (copying the same text again moves it to the top), searchable (every word must match, case- and accent-insensitive). You can also have items forgotten after a day, week, 30 or 90 days.
- **Password handling**:
  - Copies that password managers mark as concealed (`org.nspasteboard.ConcealedType` & friends) are **never recorded**. 1Password, Bitwarden, KeePassXC, Apple Passwords and Keychain Access do this.
  - Copies made while an app on the ignore list is frontmost are never recorded. The list is editable.
  - Text that *looks* like a password or API token (random mixed-case/digit/symbol strings, `ghp_…`, `sk-…`, `AKIA…`, JWTs, private keys) is kept **in memory only** for 60 s so ⇧⌘V still works. It is never written to disk and never synced. You can also choose "never store".
- **iCloud sync** across your Macs using the private CloudKit database. Clip text and timestamps are stored in CloudKit's `encryptedValues`, which are **end-to-end encrypted** with keys in your iCloud Keychain, so Apple can't read them. The stack is per-Mac; history is shared.
- **Light on resources.** It checks the pasteboard's change counter twice a second (an integer read) and only reads contents when something changed. Global shortcuts use Carbon `RegisterEventHotKey`, which is stable, needs no permission and doesn't install a keyboard tap.
- **Few moving parts.** Only public, long-stable APIs: `NSPasteboard`, Carbon hot keys, `CGEvent`, and `CKSyncEngine`. History is a JSON file written atomically (`~/Library/Application Support/PCP/history.json`, mode 600, directory mode 700).

## Build & install

Requirements: macOS 14+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

iCloud sync needs a **paid** Apple Developer Program membership. A free Apple ID cannot create an iCloud container. Its Personal Team profiles also expire after 7 days, and every re-sign asks for Accessibility again. For one Mac and no sync, use the ad-hoc install.

### This Mac, no iCloud

```sh
make install
```

That builds a Release app with the CloudKit entitlement left out, ad-hoc signs it, and copies it to `~/Applications/PCP.app`. Pass `PREFIX=/Applications` if that directory is writable. Quit the running copy from the menu bar first, so the last clipboard changes are flushed, then open the installed app. Turn on **Launch at login** in its Settings only after it lives in that folder. The registration points at that path.

History is `~/Library/Application Support/PCP/history.json`. The path does not include the bundle id, so a later signed build reads the same clips. Preferences and the Accessibility grant follow the bundle id and the code signature. Run one copy. A second copy writes the same file, and the last save wins.

### iCloud sync

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # set your Team ID + a unique bundle id
make open                                                # generates PCP.xcodeproj and opens it
```

In Xcode, select the **PCP** target, then **Signing & Capabilities**. Check that your team is set and that the iCloud container `iCloud.<your bundle id>` exists and is ticked (Xcode offers to create it). Then run.

On first launch:

1. **Accessibility.** macOS asks to let PCP control your computer. PCP needs this to send ⌘V into the app you're in. Without it, items are still put on the clipboard and you press ⌘V yourself. Rebuilding with a different signature can reset this permission. If pasting stops working, remove PCP from the list and add it back.
2. If macOS asks whether PCP may read the clipboard, choose **Allow**. Reading the clipboard is what PCP does.
3. Optional: enable **Launch at login** in Settings.

### Putting it on your other Macs

Use **Product → Archive → Distribute App → Direct Distribution**. This gives you a notarized, Developer ID–signed `PCP.app` that you copy to each Mac.

Release builds talk to the CloudKit **production** environment. Before using one, run a Debug build once and copy something so the `Clip` record type gets created. Then open [CloudKit Console](https://icloud.developer.apple.com) → your container → **Deploy Schema Changes**. You only need to do this once.

## Development

```sh
make test       # unit tests for the core logic (runs on macOS and Linux)
make build      # signed Release build (needs Config/Local.xcconfig and a paid team)
make install    # ad-hoc Release app in ~/Applications, no iCloud
```

Layout:

```
Core/      PCPCore Swift package: history, stack, dedupe/merge, secret detection, search, persistence (pure Foundation, tested)
App/       macOS app: menu bar, pasteboard monitor, hot keys, paste injection, history panel, settings, CloudKit sync
Config/    Info.plist, entitlements, signing xcconfig
```

How sync converges: each clip is a CloudKit record with a random UUID. If two Macs record the same text independently, both keep the record with the smaller UUID and delete the other, so they end up identical without coordinating. For timestamps, the newest one wins. Deletions and the history limit propagate to every device, so the smallest limit you set on any Mac applies to all of them.

## Known limits

- Text only. Images, files and rich text aren't recorded. Pasting from history pastes plain text.
- Clips over 512 KB are skipped.
- Universal Clipboard (Handoff) arrivals aren't recorded, because reading them blocks while they download. Copies made on your other PCP Macs arrive through iCloud instead.
- PCP takes ⇧⌘C and ⇧⌘V system-wide, which overrides "Paste and Match Style" and similar shortcuts in other apps.

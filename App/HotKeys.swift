import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts via Carbon's RegisterEventHotKey: no Accessibility
/// permission needed, no third-party dependency, stable for 20+ years.
@MainActor
final class HotKeyCenter {
    private struct Entry {
        let character: Character
        let modifiers: UInt32
        let action: () -> Void
        var ref: EventHotKeyRef?
    }

    private var entries: [UInt32: Entry] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x5043_5021 // 'PCP!'

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { center.entries[hotKeyID.id]?.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)

        // Shortcuts are bound to key codes, so follow keyboard layout switches.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reregisterAll() }
        }
    }

    /// Registers ⌘⇧`character` etc. Returns false if another app already owns it.
    @discardableResult
    func register(_ character: Character, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1
        entries[id] = Entry(character: character, modifiers: modifiers, action: action)
        return install(id)
    }

    private func install(_ id: UInt32) -> Bool {
        guard var entry = entries[id] else { return false }
        guard let keyCode = KeyboardLayout.keyCode(for: entry.character) ?? KeyboardLayout.ansiKeyCode(for: entry.character) else {
            Log.app.error("No key code for shortcut \(String(entry.character), privacy: .public)")
            return false
        }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), entry.modifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        entry.ref = ref
        entries[id] = entry
        if status != noErr {
            Log.app.error("Could not register shortcut for \(String(entry.character), privacy: .public): \(status)")
        }
        return status == noErr
    }

    func unregisterAll() {
        for entry in entries.values {
            if let ref = entry.ref { UnregisterEventHotKey(ref) }
        }
        entries.removeAll()
    }

    private func reregisterAll() {
        for (id, entry) in entries {
            if let ref = entry.ref { UnregisterEventHotKey(ref) }
            _ = install(id)
        }
    }
}

enum KeyboardLayout {
    /// The key code that produces `character` together with ⌘ in the current
    /// layout (so Dvorak, AZERTY, "Dvorak – QWERTY ⌘" all do the right thing).
    static func keyCode(for character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let target = Array(String(character).lowercased().utf16)
        let commandModifier = UInt32((cmdKey >> 8) & 0xFF)

        return layoutData.withUnsafeBytes { buffer -> CGKeyCode? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in UInt16(0)..<128 {
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDisplay), commandModifier,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                    &deadKeyState, chars.count, &length, &chars
                )
                if status == noErr, length == target.count, Array(chars.prefix(length)) == target {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }

    /// Fallback for layouts without Latin letters (macOS maps ⌘ shortcuts to
    /// the QWERTY positions there).
    static func ansiKeyCode(for character: Character) -> CGKeyCode? {
        guard let letter = character.lowercased().first else { return nil }
        return ansiKeys[letter].map { CGKeyCode($0) }
    }

    private static let ansiKeys: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]
}

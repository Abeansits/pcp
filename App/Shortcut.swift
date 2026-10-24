import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A global shortcut. At least one of ⌘, ⌥, or ⌃ is required, so a plain
/// letter is never stolen from the frontmost app.
struct AppShortcut: Codable, Equatable {
    var key: String
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    static let showHistory = AppShortcut(key: "c", command: true, shift: true, option: false, control: false)
    static let pasteNext = AppShortcut(key: "v", command: true, shift: true, option: false, control: false)

    var symbols: String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        text += key.uppercased()
        return text
    }

    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        if command { mask |= UInt32(cmdKey) }
        if shift { mask |= UInt32(shiftKey) }
        if option { mask |= UInt32(optionKey) }
        if control { mask |= UInt32(controlKey) }
        return mask
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        return flags
    }

    var character: Character { key.first ?? "v" }

    func addingOption() -> AppShortcut {
        var copy = self
        copy.option = true
        return copy
    }

    init(key: String, command: Bool, shift: Bool, option: Bool, control: Bool) {
        self.key = String(key.lowercased().prefix(1))
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    init?(event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command) || mods.contains(.option) || mods.contains(.control) else { return nil }
        guard event.keyCode != UInt16(kVK_Escape) else { return nil }
        guard let raw = event.charactersIgnoringModifiers?.lowercased(),
              raw.count == 1, let character = raw.first,
              let scalar = character.unicodeScalars.first, scalar.value >= 32, scalar.value < 0xF700,
              character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol
        else { return nil }
        self.init(
            key: String(character),
            command: mods.contains(.command),
            shift: mods.contains(.shift),
            option: mods.contains(.option),
            control: mods.contains(.control)
        )
    }
}

/// Click, then type a shortcut. Escape cancels.
struct ShortcutField: View {
    let title: String
    @Binding var shortcut: AppShortcut
    var reserved: AppShortcut
    var onRecording: (Bool) -> Void

    @State private var recording = false
    @State private var keys = KeyMonitor()

    var body: some View {
        LabeledContent(title) {
            Button(recording ? "Type a shortcut…" : shortcut.symbols) {
                recording.toggle()
            }
            .buttonStyle(.bordered)
            .tint(recording ? Color.accentColor : nil)
            .font(recording ? .body : .body.monospaced())
            .frame(minWidth: 148)
        }
        .onChange(of: recording) { _, isOn in
            onRecording(isOn)
            if isOn {
                listen()
            } else {
                // Removing the monitor inside its own callback is unsafe.
                DispatchQueue.main.async { keys.stop() }
            }
        }
        // Switching Settings tabs or closing the window mid-recording must
        // end it, or every global shortcut stays unregistered.
        .onDisappear {
            keys.stop()
            endRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            endRecording()
        }
    }

    /// Never called from inside the key monitor, so stopping it here is safe.
    private func endRecording() {
        guard recording else { return }
        keys.stop()
        recording = false
        onRecording(false)
    }

    private func listen() {
        let shortcut = $shortcut
        let recording = $recording
        let reserved = reserved
        keys.start { event in
            if event.keyCode == UInt16(kVK_Escape) {
                recording.wrappedValue = false
                return
            }
            guard let next = AppShortcut(event: event), next != reserved else {
                NSSound.beep()
                return
            }
            shortcut.wrappedValue = next
            recording.wrappedValue = false
        }
    }
}

private final class KeyMonitor {
    private var token: Any?

    func start(_ handle: @escaping (NSEvent) -> Void) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

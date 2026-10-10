import AppKit
import ApplicationServices

/// Sends ⌘V to the frontmost app. This is the one thing that needs the
/// Accessibility permission.
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to System Settings › Accessibility.
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Returns false (after prompting) if PCP isn't allowed to send keystrokes;
    /// the text is still on the clipboard, so a manual ⌘V works.
    @discardableResult
    static func paste() -> Bool {
        guard isTrusted else {
            requestAccess()
            return false
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        // Ignore the user's still-held ⇧ etc. while our keystroke goes through.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let v = KeyboardLayout.keyCode(for: "v") ?? KeyboardLayout.ansiKeyCode(for: "v")
        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
        return true
    }
}

import AppKit
import ApplicationServices
import PEACore

/// Moves and resizes the focused window of the frontmost app through the
/// Accessibility API.
///
/// That needs the Accessibility permission (`AXIsProcessTrusted`), which is
/// a separate grant from the one pasting uses (`CGPreflightPostEventAccess`),
/// though both switches live in the same Settings list.
@MainActor
final class WindowManager {
    private var restoreFrames = RestoreFrames<WindowKey>()
    private var didPromptThisLaunch = false

    nonisolated static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to System Settings.
    nonisolated static func requestAccess() {
        // The value of kAXTrustedCheckOptionPrompt.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    func perform(_ action: WindowAction) {
        guard Self.isTrusted else {
            // Prompt once per launch; after that, beeping is enough.
            if !didPromptThisLaunch {
                didPromptThisLaunch = true
                Self.requestAccess()
            }
            NSSound.beep()
            return
        }
        guard let window = AXWindow.focused(), let current = window.frame else {
            NSSound.beep()
            return
        }
        let key = WindowKey(element: window.element)
        let target = action == .restore
            ? restoreFrames.takeOriginal(key)
            : WindowLayout.frame(for: action, window: current, displays: Self.displays())
        guard let target else {
            NSSound.beep()
            return
        }
        let placed = window.setFrame(target, displays: Self.displays())
        if action != .restore {
            restoreFrames.record(key, from: current, to: placed)
        }
    }

    /// Every screen, in Accessibility coordinates.
    static func displays() -> [Display] {
        // screens[0] holds the menu bar; both coordinate systems start there.
        guard let mainHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSScreen.screens.map { screen in
            Display(
                frame: WindowLayout.flipped(screen.frame, mainScreenHeight: mainHeight),
                visibleFrame: WindowLayout.flipped(screen.visibleFrame, mainScreenHeight: mainHeight)
            )
        }
    }
}

/// Hashes an Accessibility element the way CoreFoundation compares them, so
/// the same window found twice maps to one entry.
private struct WindowKey: Hashable {
    let element: AXUIElement

    static func == (lhs: WindowKey, rhs: WindowKey) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

/// A window of another app.
private struct AXWindow {
    let element: AXUIElement
    let app: AXUIElement

    /// The focused window of the frontmost app. Nil for full-screen windows,
    /// windows that can't move, and PEA's own windows (asking our own process
    /// for its Accessibility tree from the main thread would block it).
    static func focused() -> AXWindow? {
        guard let running = NSWorkspace.shared.frontmostApplication,
              running.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        let app = AXUIElementCreateApplication(running.processIdentifier)
        // A hung app shouldn't freeze PEA for the default 6 seconds. The
        // timeout is per element, so the window gets it too.
        AXUIElementSetMessagingTimeout(app, 1)
        let candidate = copyElement(app, kAXFocusedWindowAttribute) ?? copyElement(app, kAXMainWindowAttribute)
        guard let candidate else { return nil }
        AXUIElementSetMessagingTimeout(candidate, 1)
        let window = AXWindow(element: candidate, app: app)
        guard !window.isFullScreen, window.isSettable(kAXPositionAttribute) else { return nil }
        return window
    }

    var frame: CGRect? {
        guard let origin = pointValue(kAXPositionAttribute), let size = sizeValue(kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Moves the window to `target` and returns where it ended up. A window
    /// with a minimum or fixed size can't take every size; it is then nudged
    /// back inside the screen.
    @discardableResult
    func setFrame(_ target: CGRect, displays: [Display]) -> CGRect {
        // With this flag on (some apps set it, and so do assistive tools),
        // every step animates and windows land in the wrong place.
        let enhanced = Self.bool(app, "AXEnhancedUserInterface")
        if enhanced { Self.set(app, "AXEnhancedUserInterface", kCFBooleanFalse) }
        defer { if enhanced { Self.set(app, "AXEnhancedUserInterface", kCFBooleanTrue) } }

        // Size first so the move isn't clamped by the old size on a smaller
        // screen, then size again in case the move changed what fits.
        setSize(target.size)
        setPosition(target.origin)
        setSize(target.size)

        guard let actual = frame else { return target }
        guard !WindowLayout.isClose(actual, target),
              let index = WindowLayout.displayIndex(for: target, among: displays)
        else { return actual }
        let nudged = WindowLayout.keptInside(
            CGRect(origin: target.origin, size: actual.size),
            bounds: displays[index].visibleFrame
        )
        setPosition(nudged.origin)
        return frame ?? nudged
    }

    // MARK: Attributes

    private var isFullScreen: Bool { Self.bool(element, "AXFullScreen") }

    private func isSettable(_ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        let status = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return status == .success && settable.boolValue
    }

    private func pointValue(_ attribute: String) -> CGPoint? {
        var point = CGPoint.zero
        guard let value = Self.axValue(element, attribute, type: .cgPoint),
              AXValueGetValue(value, .cgPoint, &point)
        else { return nil }
        return point
    }

    private func sizeValue(_ attribute: String) -> CGSize? {
        var size = CGSize.zero
        guard let value = Self.axValue(element, attribute, type: .cgSize),
              AXValueGetValue(value, .cgSize, &size)
        else { return nil }
        return size
    }

    private func setPosition(_ origin: CGPoint) {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    private func setSize(_ size: CGSize) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }

    private static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String, type: AXValueType) -> AXValue? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        return AXValueGetType(axValue) == type ? axValue : nil
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        (copy(element, attribute) as? Bool) ?? false
    }
}

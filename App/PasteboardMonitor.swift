import AppKit
import PCPCore

/// Watches the general pasteboard. macOS has no change notification, so this
/// polls `changeCount` (a cheap integer read) twice a second and only touches
/// the contents when it changed.
@MainActor
final class PasteboardMonitor {
    /// Larger copies are skipped (iCloud records max out at 1 MB).
    static let maxBytes = 512 * 1024

    var onCopy: ((_ text: String, _ sourceBundleID: String?) -> Void)?

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let remoteClipboardType = "com.apple.is-remote-clipboard"

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Puts text on the pasteboard without it being recorded as a new copy.
    /// Sensitive text is marked concealed so other clipboard tools skip it too.
    func write(_ text: String, concealed: Bool) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if concealed {
            pasteboard.setData(Data(), forType: Self.concealedType)
        }
        lastChangeCount = pasteboard.changeCount
    }

    /// Checks for a new copy right now. Also called before ⇧⌘V so a copy made
    /// a split second earlier is never missed.
    func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        // Inspect the types first: this doesn't read the contents.
        guard let types = pasteboard.types?.map(\.rawValue), !types.isEmpty else { return }
        if SecretDetector.shouldIgnore(pasteboardTypes: types) { return }
        // Universal Clipboard from another device: reading it would block while
        // it downloads; synced PCP devices deliver their copies via iCloud anyway.
        if types.contains(Self.remoteClipboardType) { return }
        // Files copied in Finder: their "text" is just a file name.
        if types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) { return }

        guard let text = pasteboard.string(forType: .string),
              text.utf8.count <= Self.maxBytes,
              !text.allSatisfy(\.isWhitespace)
        else { return }

        onCopy?(text, NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }
}

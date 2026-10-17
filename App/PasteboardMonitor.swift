import AppKit
import PCPCore

/// One copy, as plain text plus whatever formatting the source put on the pasteboard.
struct ClipboardCapture: Equatable {
    var text: String
    var html: String?
    var rtf: Data?
}

/// Watches the general pasteboard. macOS has no change notification, so this
/// polls `changeCount` (a cheap integer read) twice a second and only touches
/// the contents when it changed.
@MainActor
final class PasteboardMonitor {
    /// Larger copies are skipped (iCloud records max out at 1 MB).
    static let maxBytes = 512 * 1024

    var onCopy: ((_ capture: ClipboardCapture, _ sourceBundleID: String?) -> Void)?

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

    /// Puts an item back on the pasteboard without recording it as a new copy.
    /// Formatting is included only when `rich` is set. Sensitive text is marked
    /// concealed so other clipboard tools skip it too.
    func write(_ item: ClipItem, rich: Bool) {
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        if rich, !item.isSensitive {
            if let html = item.html {
                pasteboard.setString(html, forType: .html)
            }
            if let rtf = item.rtf {
                pasteboard.setData(rtf, forType: .rtf)
            }
        }
        if item.isSensitive {
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

        var html = pasteboard.string(forType: .html)
        if html?.utf8.count ?? 0 > Self.maxBytes { html = nil }
        var rtf = pasteboard.data(forType: .rtf)
        if rtf?.count ?? 0 > Self.maxBytes { rtf = nil }
        if html != nil { rtf = nil }

        onCopy?(
            ClipboardCapture(text: text, html: html, rtf: rtf),
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
    }
}

import Foundation

/// One clipboard entry. `text` is always plain. `html` or `rtf` is kept when
/// the copy had formatting, and is only put back on the pasteboard on request.
public struct ClipItem: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var text: String
    /// When this text was first copied (on any device).
    public var createdAt: Date
    /// When it was last copied or picked. History is ordered by this, newest first.
    public var lastUsedAt: Date
    /// Looked like a password/token. Sensitive items live in memory only:
    /// never written to disk, never synced, and they expire.
    public var isSensitive: Bool
    public var expiresAt: Date?
    /// HTML from the pasteboard, when the copy had formatting or links.
    /// Plain text stays `text`. Nil when the copy was plain, or when the
    /// item is sensitive.
    public var html: String?
    /// RTF from the pasteboard, kept only when there was no HTML.
    public var rtf: Data?

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date,
        lastUsedAt: Date? = nil,
        isSensitive: Bool = false,
        expiresAt: Date? = nil,
        html: String? = nil,
        rtf: Data? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt ?? createdAt
        self.isSensitive = isSensitive
        self.expiresAt = expiresAt
        self.html = isSensitive ? nil : html
        self.rtf = isSensitive ? nil : (html == nil ? rtf : nil)
    }

    public var hasRichText: Bool { html != nil || rtf != nil }

    /// Single-line preview with whitespace collapsed, for the menu and tooltip.
    public func preview(maxLength: Int = 200) -> String {
        if isSensitive { return String(repeating: "•", count: min(max(text.count, 8), 16)) }
        var out = ""
        out.reserveCapacity(min(text.utf8.count, maxLength))
        var lastWasSpace = false
        for ch in text {
            if ch.isWhitespace {
                if !lastWasSpace && !out.isEmpty { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(ch)
                lastWasSpace = false
            }
            if out.count >= maxLength { out.append("…"); break }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// At most two lines for a history row. Blank lines are skipped so a
    /// paragraph break still shows the next sentence. The stored text is
    /// left as copied, including its original line breaks.
    public func listPreview(maxLines: Int = 2) -> String {
        if isSensitive { return preview() }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
        var lines: [String] = []
        var more = false
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if lines.count == maxLines {
                more = true
                break
            }
            lines.append(line)
        }
        guard var last = lines.last else { return preview() }
        if more { last += "…"; lines[lines.count - 1] = last }
        return lines.joined(separator: "\n")
    }
}

/// Which item ⇧⌘V pastes next.
public enum PasteOrder: String, Codable, CaseIterable, Sendable {
    /// copy A, B, C → paste C, B, A
    case lastInFirstOut
    /// copy A, B, C → paste A, B, C
    case firstInFirstOut
}

/// Changes that need to be pushed to iCloud.
public struct SyncDelta: Equatable, Sendable {
    public var saved: Set<UUID> = []
    public var deleted: Set<UUID> = []

    public init(saved: Set<UUID> = [], deleted: Set<UUID> = []) {
        self.saved = saved
        self.deleted = deleted
    }

    public var isEmpty: Bool { saved.isEmpty && deleted.isEmpty }

    public mutating func save(_ id: UUID) {
        deleted.remove(id)
        saved.insert(id)
    }

    public mutating func delete(_ id: UUID) {
        saved.remove(id)
        deleted.insert(id)
    }

    public mutating func formUnion(_ other: SyncDelta) {
        for id in other.saved { save(id) }
        for id in other.deleted { delete(id) }
    }
}

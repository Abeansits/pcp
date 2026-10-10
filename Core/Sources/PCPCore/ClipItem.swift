import Foundation

/// One clipboard entry. Only plain text is stored.
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

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date,
        lastUsedAt: Date? = nil,
        isSensitive: Bool = false,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt ?? createdAt
        self.isSensitive = isSensitive
        self.expiresAt = expiresAt
    }

    /// Single-line preview with whitespace collapsed, for list rows.
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

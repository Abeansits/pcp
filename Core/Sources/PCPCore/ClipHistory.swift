import Foundation

/// Clipboard history plus the paste stack.
///
/// - `items` is the full history, newest first, capped at `capacity`. It is
///   what gets searched and synced.
/// - `stack` is the local paste stack: ids of things copied on *this* Mac that
///   haven't been pasted with ⇧⌘V yet. Items synced in from other devices are
///   added to history but not to the stack. Copying after a pause of
///   `stackIdleTimeout` starts a fresh stack, so ⇧⌘V never digs up something
///   copied hours ago (which matters most in copy order).
///
/// Every mutation returns a `SyncDelta` describing what must be pushed to the
/// cloud. Sensitive items are never uploaded. A normal item that is later
/// recognized as a secret is deleted from the cloud instead.
public struct ClipHistory: Codable, Equatable, Sendable {
    public static let defaultCapacity = 1000
    public static let stackCapacity = 100
    public static let stackIdleTimeout: TimeInterval = 15 * 60

    public private(set) var items: [ClipItem] = []
    /// Bottom … top. The top (most recent push) is the last element.
    public private(set) var stack: [UUID] = []
    /// Last push to or pop from the stack.
    public private(set) var stackUpdatedAt: Date?
    public private(set) var capacity: Int

    public init(capacity: Int = ClipHistory.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    // MARK: Queries

    public func item(_ id: UUID) -> ClipItem? {
        items.first { $0.id == id }
    }

    public func isOnStack(_ id: UUID) -> Bool {
        stack.contains(id)
    }

    /// The item ⇧⌘V would paste, without removing it.
    public func peek(order: PasteOrder) -> ClipItem? {
        let id = order == .lastInFirstOut ? stack.last : stack.first
        return id.flatMap(item)
    }

    /// All query terms must appear (case- and diacritic-insensitive).
    /// Sensitive items are never matched by a non-empty query.
    public func search(_ query: String) -> [ClipItem] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return items }
        return items.filter { item in
            !item.isSensitive && terms.allSatisfy {
                item.text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    // MARK: Local changes

    /// Something was copied on this Mac: add it to history (or bump the
    /// existing entry with the same text) and push it onto the paste stack.
    @discardableResult
    public mutating func record(
        _ text: String,
        sensitive: Bool = false,
        expiresAt: Date? = nil,
        now: Date = Date()
    ) -> SyncDelta {
        var delta = SyncDelta()
        let id: UUID
        if let index = items.firstIndex(where: { $0.text == text }) {
            var existing = items.remove(at: index)
            existing.lastUsedAt = max(existing.lastUsedAt, now)
            if sensitive {
                // A later copy that looks like a secret wins, and the cloud
                // copy of the earlier normal item has to go.
                if !existing.isSensitive { delta.delete(existing.id) }
                existing.isSensitive = true
                existing.expiresAt = expiresAt
            } else if existing.isSensitive {
                // Copied again with secret handling off: it becomes a normal clip.
                existing.isSensitive = false
                existing.expiresAt = nil
            }
            insertSorted(existing)
            id = existing.id
            if !existing.isSensitive { delta.save(id) }
        } else {
            let item = ClipItem(
                text: text,
                createdAt: now,
                isSensitive: sensitive,
                expiresAt: sensitive ? expiresAt : nil
            )
            insertSorted(item)
            id = item.id
            if !sensitive { delta.save(id) }
        }
        if let last = stackUpdatedAt, now.timeIntervalSince(last) > Self.stackIdleTimeout {
            stack.removeAll()
        }
        stack.removeAll { $0 == id }
        stack.append(id)
        stackUpdatedAt = now
        if stack.count > Self.stackCapacity {
            stack.removeFirst(stack.count - Self.stackCapacity)
        }
        delta.formUnion(evictOverflow())
        return delta
    }

    /// ⇧⌘V: take the next item off the paste stack. History is untouched.
    public mutating func pop(order: PasteOrder, now: Date = Date()) -> ClipItem? {
        if !stack.isEmpty { stackUpdatedAt = now }
        while !stack.isEmpty {
            let id = order == .lastInFirstOut ? stack.removeLast() : stack.removeFirst()
            if let item = item(id) { return item }
        }
        return nil
    }

    /// Forget what's waiting on the paste stack. History is untouched.
    public mutating func clearStack() {
        stack.removeAll()
    }

    /// An item was picked from the panel: move it to the top of history and
    /// take it off the paste stack (it has been used).
    @discardableResult
    public mutating func use(_ id: UUID, now: Date = Date()) -> SyncDelta {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return SyncDelta() }
        var item = items.remove(at: index)
        item.lastUsedAt = max(item.lastUsedAt, now)
        insertSorted(item)
        stack.removeAll { $0 == id }
        return item.isSensitive ? SyncDelta() : SyncDelta(saved: [id])
    }

    @discardableResult
    public mutating func delete(_ ids: Set<UUID>) -> SyncDelta {
        var delta = SyncDelta()
        items.removeAll { item in
            guard ids.contains(item.id) else { return false }
            if !item.isSensitive { delta.delete(item.id) }
            return true
        }
        stack.removeAll { ids.contains($0) }
        return delta
    }

    @discardableResult
    public mutating func removeAll() -> SyncDelta {
        delete(Set(items.map(\.id)))
    }

    /// Drops sensitive items past their expiry and, if `olderThan` is set,
    /// anything not used since then.
    @discardableResult
    public mutating func purgeExpired(now: Date = Date(), olderThan cutoff: Date? = nil) -> SyncDelta {
        let expired = items.filter { item in
            if let expiry = item.expiresAt, expiry <= now { return true }
            if let cutoff, item.lastUsedAt < cutoff { return true }
            return false
        }
        return expired.isEmpty ? SyncDelta() : delete(Set(expired.map(\.id)))
    }

    @discardableResult
    public mutating func setCapacity(_ newValue: Int) -> SyncDelta {
        capacity = max(1, newValue)
        return evictOverflow()
    }

    // MARK: Remote changes

    /// Applies a record fetched from iCloud. Returns what must be pushed back,
    /// e.g. when two devices independently created an entry for the same text:
    /// both keep the entry with the smaller id and delete the other, so all
    /// devices converge without coordination.
    @discardableResult
    public mutating func applyRemote(
        id: UUID,
        text: String,
        createdAt: Date,
        lastUsedAt: Date
    ) -> SyncDelta {
        var delta = SyncDelta()
        var incoming = ClipItem(id: id, text: text, createdAt: createdAt, lastUsedAt: lastUsedAt)

        if let index = items.firstIndex(where: { $0.id == id }) {
            let local = items.remove(at: index)
            if local.isSensitive {
                // The server still has the plaintext (the upgrade's delete
                // lost the race, or a peer saved over it). Drop that record.
                insertSorted(local)
                return SyncDelta(deleted: [id])
            }
            incoming.createdAt = min(local.createdAt, createdAt)
            incoming.lastUsedAt = max(local.lastUsedAt, lastUsedAt)
            insertSorted(incoming)
            if incoming.lastUsedAt != lastUsedAt || incoming.createdAt != createdAt {
                delta.save(id) // we know something newer than the server
            }
        } else if let index = items.firstIndex(where: { $0.text == text }) {
            let local = items.remove(at: index)
            if local.isSensitive {
                // Another device stored this text in the clear. Keep the
                // memory-only copy and delete theirs.
                insertSorted(local)
                return SyncDelta(deleted: [id])
            }
            let merged = ClipItem(
                id: local.id.uuidString < id.uuidString ? local.id : id,
                text: text,
                createdAt: min(local.createdAt, createdAt),
                lastUsedAt: max(local.lastUsedAt, lastUsedAt)
            )
            insertSorted(merged)
            if let stackIndex = stack.firstIndex(of: local.id) { stack[stackIndex] = merged.id }
            let loser = merged.id == id ? local.id : id
            delta.delete(loser)
            if merged.id != id || merged.lastUsedAt != lastUsedAt || merged.createdAt != createdAt {
                delta.save(merged.id)
            }
        } else {
            insertSorted(incoming)
        }
        delta.formUnion(evictOverflow())
        return delta
    }

    /// A record was deleted in iCloud (by another device).
    public mutating func applyRemoteDeletion(_ id: UUID) {
        // A peer may delete the cloud record of a clip we have since marked
        // sensitive. The memory-only item, and its place on the paste stack,
        // stay until it expires.
        if items.contains(where: { $0.id == id && $0.isSensitive }) { return }
        items.removeAll { $0.id == id }
        stack.removeAll { $0 == id }
    }

    /// The cloud zone was wiped: drop everything that came from / went to it.
    public mutating func removeAllSynced() {
        items.removeAll { !$0.isSensitive }
        stack.removeAll { id in !items.contains { $0.id == id } }
    }

    // MARK: Persistence

    /// A copy safe to write to disk: no sensitive items.
    public func persistable() -> ClipHistory {
        var copy = self
        copy.items.removeAll(where: \.isSensitive)
        copy.stack.removeAll { id in !copy.items.contains { $0.id == id } }
        return copy
    }

    // MARK: Private

    private mutating func insertSorted(_ item: ClipItem) {
        let index = items.firstIndex { $0.lastUsedAt < item.lastUsedAt } ?? items.endIndex
        items.insert(item, at: index)
    }

    private mutating func evictOverflow() -> SyncDelta {
        guard items.count > capacity else { return SyncDelta() }
        let evicted = items[capacity...]
        return delete(Set(evicted.map(\.id)))
    }
}

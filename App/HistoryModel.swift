import Foundation
import PCPCore

/// Owns the in-memory history, saves it to disk (debounced), expires old and
/// sensitive items, and reports cloud-relevant changes through `onDelta`.
@MainActor
final class HistoryModel: ObservableObject {
    @Published private(set) var history: ClipHistory

    /// Called with every change that must be pushed to iCloud.
    var onDelta: ((SyncDelta) -> Void)?

    private let file: HistoryFile
    private let prefs: Preferences
    private var pendingSave: DispatchWorkItem?
    private var purgeTimer: Timer?

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PCP", isDirectory: true)
    }

    init(prefs: Preferences) {
        self.prefs = prefs
        file = HistoryFile(url: Self.supportDirectory.appendingPathComponent("history.json"))
        var loaded = file.load() ?? ClipHistory(capacity: prefs.historyLimit)
        loaded.setCapacity(prefs.historyLimit)
        history = loaded

        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purgeExpired() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        purgeTimer = timer
    }

    // MARK: Mutations

    func record(_ text: String, html: String?, rtf: Data?, sensitive: Bool, expiresAt: Date?) {
        mutate { $0.record(text, html: html, rtf: rtf, sensitive: sensitive, expiresAt: expiresAt) }
    }

    func pop(order: PasteOrder) -> ClipItem? {
        var item: ClipItem?
        mutate { item = $0.pop(order: order); return SyncDelta() }
        return item
    }

    func use(_ id: UUID) { mutate { $0.use(id) } }
    func delete(_ id: UUID) { mutate { $0.delete([id]) } }
    func removeAll() { mutate { $0.removeAll() } }
    func clearStack() { mutate { $0.clearStack(); return SyncDelta() } }
    func removeFromStack(_ id: UUID) { mutate { $0.removeFromStack(id); return SyncDelta() } }
    func moveOnStack(_ id: UUID, sooner: Bool, order: PasteOrder) {
        mutate { $0.moveOnStack(id, sooner: sooner, order: order); return SyncDelta() }
    }
    func setCapacity(_ capacity: Int) { mutate { $0.setCapacity(capacity) } }

    func applyRemote(id: UUID, text: String, createdAt: Date, lastUsedAt: Date) {
        mutate { $0.applyRemote(id: id, text: text, createdAt: createdAt, lastUsedAt: lastUsedAt) }
    }

    func applyRemoteDeletion(_ id: UUID) {
        guard history.item(id) != nil else { return }
        mutate { $0.applyRemoteDeletion(id); return SyncDelta() }
    }

    func removeAllSynced() { mutate { $0.removeAllSynced(); return SyncDelta() } }

    /// Everything that should exist in iCloud, for a full re-upload.
    var syncableIDs: Set<UUID> {
        Set(history.items.lazy.filter { !$0.isSensitive }.map(\.id))
    }

    func purgeExpired() {
        let now = Date()
        let cutoff = prefs.forgetAfterDays > 0
            ? now.addingTimeInterval(-Double(prefs.forgetAfterDays) * 86_400)
            : nil
        // Work on a copy so an idle tick doesn't trigger a UI refresh.
        var copy = history
        let delta = copy.purgeExpired(now: now, olderThan: cutoff)
        guard copy.items.count != history.items.count else { return }
        history = copy
        scheduleSave()
        if !delta.isEmpty { onDelta?(delta) }
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try file.save(history)
        } catch {
            Log.app.error("Saving history failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Private

    private func mutate(_ body: (inout ClipHistory) -> SyncDelta) {
        let delta = body(&history)
        scheduleSave()
        if !delta.isEmpty { onDelta?(delta) }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
}

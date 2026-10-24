import CloudKit
import Foundation
import PEACore
import Security

/// Syncs history through the user's private iCloud database with CKSyncEngine.
///
/// Privacy: clip text and timestamps are stored in `encryptedValues`, which
/// CloudKit encrypts end-to-end with keys from the user's iCloud Keychain —
/// Apple can't read them. Only the record id (a random UUID) is plaintext.
@MainActor
final class CloudSync: ObservableObject {
    enum Status: Equatable {
        case off
        case unavailable(String)
        case syncing
        case upToDate(Date)
        case error(String)

        var description: String {
            switch self {
            case .off: "Off"
            case .unavailable(let reason): reason
            case .syncing: "Syncing…"
            case .upToDate(let date): "Up to date (\(date.formatted(date: .omitted, time: .shortened)))"
            case .error(let message): "Error: \(message)"
            }
        }
    }

    @Published private(set) var status: Status = .off

    static let zoneID = CKRecordZone.ID(zoneName: "Clips", ownerName: CKCurrentUserDefaultName)
    static let recordType: CKRecord.RecordType = "Clip"
    private static let maxRecordsPerBatch = 100

    private let model: HistoryModel
    private var engine: CKSyncEngine?
    private var metadata: Metadata
    private let metadataURL = HistoryModel.supportDirectory.appendingPathComponent("sync-state.json")
    private var pendingMetadataSave: DispatchWorkItem?
    private var safetyNetTimer: Timer?

    /// Engine state plus the last known server "system fields" (change tags)
    /// of each record, so updates don't conflict with ourselves.
    private struct Metadata: Codable {
        var engineState: CKSyncEngine.State.Serialization?
        var systemFields: [String: Data] = [:]
    }

    init(model: HistoryModel) {
        self.model = model
        if let data = try? Data(contentsOf: metadataURL),
           let decoded = try? JSONDecoder().decode(Metadata.self, from: data) {
            metadata = decoded
        } else {
            metadata = Metadata()
        }
    }

    // MARK: Lifecycle

    func start() {
        guard engine == nil else { return }
        // CKContainer traps if the app isn't signed with the iCloud entitlement
        // (e.g. a quick unsigned local build), so check first.
        guard Self.hasCloudKitEntitlement else {
            status = .unavailable("Unavailable: this build isn't signed with iCloud")
            return
        }
        let database = CKContainer.default().privateCloudDatabase
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: metadata.engineState,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine

        if metadata.engineState == nil {
            // First run (or sync was re-enabled): make sure the zone exists and
            // upload everything we have. Duplicates merge on arrival.
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            enqueue(SyncDelta(saved: model.syncableIDs))
        }

        // Push notifications trigger fetches; this is a belt-and-braces fallback.
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNow() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        safetyNetTimer = timer
        syncNow()
    }

    /// Turns sync off. Local history is kept; turning it back on re-uploads it.
    func stop() {
        safetyNetTimer?.invalidate()
        safetyNetTimer = nil
        if let engine {
            Task { await engine.cancelOperations() }
        }
        engine = nil
        metadata = Metadata()
        saveMetadataNow()
        status = .off
    }

    func syncNow() {
        guard let engine else { return }
        Task {
            do {
                try await engine.fetchChanges()
                try await engine.sendChanges()
            } catch {
                Log.sync.error("Sync failed: \(error.localizedDescription, privacy: .public)")
                self.status = .error(error.localizedDescription)
            }
        }
    }

    /// Queues local changes for upload. CKSyncEngine batches and sends them
    /// shortly after, and retries on its own when offline.
    func enqueue(_ delta: SyncDelta) {
        guard let engine, !delta.isEmpty else { return }
        let saves = delta.saved.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(Self.recordID($0)) }
        let deletes = delta.deleted.map { CKSyncEngine.PendingRecordZoneChange.deleteRecord(Self.recordID($0)) }
        engine.state.add(pendingRecordZoneChanges: saves + deletes)
    }

    // MARK: Records

    private static func recordID(_ id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    private func makeRecord(_ recordID: CKRecord.ID) -> CKRecord? {
        guard let id = UUID(uuidString: recordID.recordName),
              let item = model.history.item(id),
              !item.isSensitive
        else { return nil }
        let record = cachedRecord(recordID) ?? CKRecord(recordType: Self.recordType, recordID: recordID)
        record.encryptedValues["text"] = item.text
        record.encryptedValues["createdAt"] = item.createdAt
        record.encryptedValues["lastUsedAt"] = item.lastUsedAt
        return record
    }

    private func apply(_ record: CKRecord) {
        guard record.recordType == Self.recordType,
              let id = UUID(uuidString: record.recordID.recordName),
              let text = record.encryptedValues["text"] as? String
        else { return }
        let createdAt = record.encryptedValues["createdAt"] as? Date ?? record.creationDate ?? Date()
        let lastUsedAt = record.encryptedValues["lastUsedAt"] as? Date ?? createdAt
        storeSystemFields(record)
        model.applyRemote(id: id, text: text, createdAt: createdAt, lastUsedAt: lastUsedAt)
    }

    private func cachedRecord(_ recordID: CKRecord.ID) -> CKRecord? {
        guard let data = metadata.systemFields[recordID.recordName],
              let coder = try? NSKeyedUnarchiver(forReadingFrom: data)
        else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    private func storeSystemFields(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        metadata.systemFields[record.recordID.recordName] = coder.encodedData
        scheduleMetadataSave()
    }

    private func forgetSystemFields(_ recordID: CKRecord.ID) {
        metadata.systemFields[recordID.recordName] = nil
        scheduleMetadataSave()
    }

    private func uploadEverything(using engine: CKSyncEngine) {
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        enqueue(SyncDelta(saved: model.syncableIDs))
    }

    // MARK: Persistence

    private func scheduleMetadataSave() {
        pendingMetadataSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveMetadataNow() }
        }
        pendingMetadataSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func saveMetadataNow() {
        pendingMetadataSave?.cancel()
        pendingMetadataSave = nil
        do {
            let directory = metadataURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadataURL.path)
        } catch {
            Log.sync.error("Saving sync state failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static var hasCloudKitEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil)
        return (value as? [String])?.contains("CloudKit") ?? false
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudSync: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            metadata.engineState = update.stateSerialization
            scheduleMetadataSave()

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                uploadEverything(using: syncEngine)
            case .signOut, .switchAccounts:
                // Keep local history; just forget what we knew about the server.
                metadata.systemFields.removeAll()
                scheduleMetadataSave()
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == Self.zoneID {
                metadata.systemFields.removeAll()
                scheduleMetadataSave()
                switch deletion.reason {
                case .deleted, .purged:
                    // Wiped from another device or via iCloud settings.
                    model.removeAllSynced()
                case .encryptedDataReset:
                    // User reset their iCloud Keychain: re-upload with new keys.
                    uploadEverything(using: syncEngine)
                @unknown default:
                    break
                }
            }

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                apply(modification.record)
            }
            for deletion in changes.deletions {
                forgetSystemFields(deletion.recordID)
                if let id = UUID(uuidString: deletion.recordID.recordName) {
                    model.applyRemoteDeletion(id)
                }
            }

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                storeSystemFields(record)
            }
            for recordID in sent.deletedRecordIDs {
                forgetSystemFields(recordID)
            }
            for failure in sent.failedRecordSaves {
                handleFailedSave(failure.record.recordID, error: failure.error, engine: syncEngine)
            }

        case .willFetchChanges, .willSendChanges:
            status = .syncing

        case .didFetchChanges, .didSendChanges:
            if case .syncing = status { status = .upToDate(Date()) }

        case .sentDatabaseChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break

        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        // Build records here on the main actor; the provider closure below runs elsewhere.
        var records: [CKRecord.ID: CKRecord] = [:]
        var batch: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in pending {
            guard batch.count < Self.maxRecordsPerBatch else { break }
            switch change {
            case .saveRecord(let recordID):
                if let record = makeRecord(recordID) {
                    records[recordID] = record
                    batch.append(change)
                } else {
                    // Deleted or now sensitive locally: nothing to save.
                    syncEngine.state.remove(pendingRecordZoneChanges: [change])
                }
            case .deleteRecord:
                batch.append(change)
            @unknown default:
                break
            }
        }
        guard !batch.isEmpty else { return nil }
        let snapshot = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: batch) { snapshot[$0] }
    }

    private func handleFailedSave(_ recordID: CKRecord.ID, error: CKError, engine: CKSyncEngine) {
        switch error.code {
        case .serverRecordChanged:
            // Another device updated it. Merge (newest timestamp wins); if ours
            // is newer, applyRemote queues a re-save with the fresh change tag.
            if let serverRecord = error.serverRecord {
                apply(serverRecord)
            }
        case .zoneNotFound:
            forgetSystemFields(recordID)
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .unknownItem:
            forgetSystemFields(recordID)
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
             .notAuthenticated, .operationCancelled, .requestRateLimited:
            break // CKSyncEngine retries these by itself.
        case .quotaExceeded:
            status = .error("iCloud storage is full")
        default:
            Log.sync.error("Saving record failed: \(error.localizedDescription, privacy: .public)")
            status = .error(error.localizedDescription)
        }
    }
}

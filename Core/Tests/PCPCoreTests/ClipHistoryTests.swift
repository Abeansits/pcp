import Foundation
import XCTest
@testable import PCPCore

final class ClipHistoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func t(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testCopyCopyCopyPastePastePasteLIFO() {
        var h = ClipHistory()
        h.record("A", now: t(1))
        h.record("B", now: t(2))
        h.record("C", now: t(3))
        XCTAssertEqual(h.pop(order: .lastInFirstOut)?.text, "C")
        XCTAssertEqual(h.pop(order: .lastInFirstOut)?.text, "B")
        XCTAssertEqual(h.pop(order: .lastInFirstOut)?.text, "A")
        XCTAssertNil(h.pop(order: .lastInFirstOut))
        // History is untouched by popping.
        XCTAssertEqual(h.items.map(\.text), ["C", "B", "A"])
    }

    func testCopyCopyCopyPastePastePasteFIFO() {
        var h = ClipHistory()
        h.record("A", now: t(1))
        h.record("B", now: t(2))
        h.record("C", now: t(3))
        XCTAssertEqual(h.peek(order: .firstInFirstOut)?.text, "A")
        XCTAssertEqual(h.pop(order: .firstInFirstOut)?.text, "A")
        XCTAssertEqual(h.pop(order: .firstInFirstOut)?.text, "B")
        XCTAssertEqual(h.pop(order: .firstInFirstOut)?.text, "C")
        XCTAssertNil(h.pop(order: .firstInFirstOut))
    }

    func testClearStackKeepsHistory() {
        var h = ClipHistory()
        h.record("A", now: t(1))
        h.record("B", now: t(2))
        h.clearStack()
        XCTAssertNil(h.pop(order: .lastInFirstOut))
        XCTAssertEqual(h.items.count, 2)
    }

    func testRecopyBumpsInsteadOfDuplicating() {
        var h = ClipHistory()
        let first = h.record("A", now: t(1))
        h.record("B", now: t(2))
        let again = h.record("A", now: t(3))
        XCTAssertEqual(h.items.map(\.text), ["A", "B"])
        XCTAssertEqual(first.saved, again.saved, "same item id is re-saved")
        XCTAssertEqual(h.items[0].createdAt, t(1))
        XCTAssertEqual(h.items[0].lastUsedAt, t(3))
        XCTAssertEqual(h.stack.count, 2)
        XCTAssertEqual(h.pop(order: .lastInFirstOut)?.text, "A")
    }

    func testCapacityEvictsOldestAndReportsDeletion() {
        var h = ClipHistory(capacity: 2)
        let a = h.record("A", now: t(1)).saved.first!
        h.record("B", now: t(2))
        let delta = h.record("C", now: t(3))
        XCTAssertEqual(h.items.map(\.text), ["C", "B"])
        XCTAssertEqual(delta.deleted, [a])
        XCTAssertFalse(h.isOnStack(a))

        let shrink = h.setCapacity(1)
        XCTAssertEqual(h.items.map(\.text), ["C"])
        XCTAssertEqual(shrink.deleted.count, 1)
    }

    func testUseMovesToTopAndConsumesStackEntry() {
        var h = ClipHistory()
        let a = h.record("A", now: t(1)).saved.first!
        h.record("B", now: t(2))
        let delta = h.use(a, now: t(3))
        XCTAssertEqual(delta.saved, [a])
        XCTAssertEqual(h.items.map(\.text), ["A", "B"])
        XCTAssertFalse(h.isOnStack(a))
        XCTAssertEqual(h.pop(order: .lastInFirstOut)?.text, "B")
    }

    func testSensitiveItemsAreNeverSyncedOrPersistedAndExpire() {
        var h = ClipHistory()
        h.record("normal", now: t(1))
        let delta = h.record("hunter2!X", sensitive: true, expiresAt: t(60), now: t(2))
        XCTAssertTrue(delta.isEmpty)
        XCTAssertEqual(h.items.count, 2)
        XCTAssertEqual(h.pop(order: .lastInFirstOut)?.text, "hunter2!X", "still pasteable while alive")

        XCTAssertEqual(h.persistable().items.map(\.text), ["normal"])
        XCTAssertTrue(h.search("hunter").isEmpty)

        let purge = h.purgeExpired(now: t(61))
        XCTAssertTrue(purge.isEmpty)
        XCTAssertEqual(h.items.map(\.text), ["normal"])
    }

    func testPurgeOlderThanCutoff() {
        var h = ClipHistory()
        h.record("old", now: t(1))
        h.record("new", now: t(100))
        let delta = h.purgeExpired(now: t(100), olderThan: t(50))
        XCTAssertEqual(h.items.map(\.text), ["new"])
        XCTAssertEqual(delta.deleted.count, 1)
    }

    func testSearchMatchesAllTermsCaseAndDiacriticInsensitive() {
        var h = ClipHistory()
        h.record("Pull the feature branch from GitHub", now: t(1))
        h.record("Café meeting at 10am", now: t(2))
        h.record("invoice PDF path", now: t(3))
        XCTAssertEqual(h.search("github PULL").map(\.text), ["Pull the feature branch from GitHub"])
        XCTAssertEqual(h.search("cafe").map(\.text), ["Café meeting at 10am"])
        XCTAssertEqual(h.search("").count, 3)
        XCTAssertTrue(h.search("nope").isEmpty)
    }

    func testDeleteAndRemoveAll() {
        var h = ClipHistory()
        let a = h.record("A", now: t(1)).saved.first!
        h.record("B", now: t(2))
        XCTAssertEqual(h.delete([a]).deleted, [a])
        XCTAssertEqual(h.items.map(\.text), ["B"])
        XCTAssertEqual(h.removeAll().deleted.count, 1)
        XCTAssertTrue(h.items.isEmpty)
        XCTAssertTrue(h.stack.isEmpty)
    }

    // MARK: Remote

    func testRemoteInsertGoesToHistoryNotStack() {
        var h = ClipHistory()
        h.record("local", now: t(5))
        let delta = h.applyRemote(id: UUID(), text: "remote", createdAt: t(1), lastUsedAt: t(1))
        XCTAssertTrue(delta.isEmpty)
        XCTAssertEqual(h.items.map(\.text), ["local", "remote"])
        XCTAssertEqual(h.stack.count, 1)
    }

    func testRemoteUpdateOfKnownItemKeepsNewestTimestamp() {
        var h = ClipHistory()
        let id = h.record("A", now: t(10)).saved.first!
        h.record("B", now: t(20))
        // Server says A was used at t(30): moves to top, nothing to push back.
        XCTAssertTrue(h.applyRemote(id: id, text: "A", createdAt: t(10), lastUsedAt: t(30)).isEmpty)
        XCTAssertEqual(h.items.map(\.text), ["A", "B"])
        // Server has a stale copy: we push ours back.
        XCTAssertEqual(h.applyRemote(id: id, text: "A", createdAt: t(10), lastUsedAt: t(5)).saved, [id])
        XCTAssertEqual(h.item(id)?.lastUsedAt, t(30))
    }

    func testSameTextOnTwoDevicesConvergesOnOneId() {
        let idX = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let idY = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!

        // Device 1 created idX locally, receives idY from device 2.
        var d1 = ClipHistory()
        d1.applyRemote(id: idX, text: "same", createdAt: t(1), lastUsedAt: t(1))
        let delta1 = d1.applyRemote(id: idY, text: "same", createdAt: t(2), lastUsedAt: t(3))
        XCTAssertEqual(d1.items.map(\.id), [idX])
        XCTAssertEqual(d1.items[0].lastUsedAt, t(3))
        XCTAssertEqual(delta1.deleted, [idY])
        XCTAssertEqual(delta1.saved, [idX])

        // Device 2 copied the same text locally (random id, on its stack), receives idX.
        var d2 = ClipHistory()
        d2.record("same", now: t(3))
        let localId = d2.items[0].id
        let delta2 = d2.applyRemote(id: idX, text: "same", createdAt: t(1), lastUsedAt: t(1))
        XCTAssertEqual(d2.items.map(\.id), [idX])
        XCTAssertEqual(d2.items[0].lastUsedAt, t(3))
        XCTAssertEqual(delta2.deleted, [localId])
        XCTAssertEqual(delta2.saved, [idX])
        XCTAssertEqual(d2.stack, [idX], "stack entry follows the surviving id")
    }

    func testRemoteDeletionAndZoneWipe() {
        var h = ClipHistory()
        let a = h.record("A", now: t(1)).saved.first!
        h.record("secret!Ab1", sensitive: true, expiresAt: t(100), now: t(2))
        h.applyRemote(id: UUID(), text: "R", createdAt: t(3), lastUsedAt: t(3))
        h.applyRemoteDeletion(a)
        XCTAssertNil(h.item(a))
        XCTAssertFalse(h.isOnStack(a))
        h.removeAllSynced()
        XCTAssertEqual(h.items.map(\.text), ["secret!Ab1"])
    }

    // MARK: Persistence

    func testFileRoundTripDropsSensitive() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = HistoryFile(url: dir.appendingPathComponent("history.json"))
        XCTAssertNil(file.load())

        var h = ClipHistory(capacity: 50)
        h.record("A", now: t(1))
        h.record("pw!Ab1xyz", sensitive: true, expiresAt: t(60), now: t(2))
        try file.save(h)

        let loaded = try XCTUnwrap(file.load())
        XCTAssertEqual(loaded.items.map(\.text), ["A"])
        XCTAssertEqual(loaded.capacity, 50)
        XCTAssertEqual(loaded.stack, [h.items[1].id])
        let perms = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }

    func testPreviewCollapsesWhitespaceAndMasksSecrets() {
        let item = ClipItem(text: "  hello\n\n  world\t!  ", createdAt: t0)
        XCTAssertEqual(item.preview(), "hello world !")
        let secret = ClipItem(text: "abc", createdAt: t0, isSensitive: true)
        XCTAssertEqual(secret.preview(), "••••••••")
    }
}

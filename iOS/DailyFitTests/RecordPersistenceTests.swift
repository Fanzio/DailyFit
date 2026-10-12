import XCTest
import Foundation
@testable import DailyFit

final class RecordPersistenceTests: XCTestCase {
    private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func database(_ folder: URL) -> SQLiteRecords { SQLiteRecords(url: folder.appendingPathComponent("records-v3.sqlite")) }

    func testEditingOneNoteWritesOnlyItsRecord() async throws {
        let folder = folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder)
        var data = try SeedCatalog.initialData()
        data.notes = [DiaryNote(title: "Nota", body: "Testo")]
        try await repository.save(data, revision: 1)
        let db = database(folder), before = try db.read()
        data.notes[0].body = "Testo modificato"
        try await repository.save(data, revision: 2)
        let after = try db.read(), key = "notes/" + data.notes[0].id.uuidString
        XCTAssertEqual(Set(after.keys.filter { before[$0] != after[$0] }), [key])
        let written = await repository.lastWrittenBytes
        XCTAssertLessThan(written, 1_000)
    }

    func testChangingLoadWritesOnlySelectedDay() async throws {
        let folder = folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder)
        var data = try SeedCatalog.initialData()
        try await repository.save(data, revision: 1)
        data.plans[0].days[0].entries[0].sets[0].load = 42.5
        try await repository.save(data, revision: 2)
        let keys = await repository.lastWrittenKeys
        XCTAssertEqual(keys, ["plans/" + data.plans[0].id.uuidString + "/day/" + data.plans[0].days[0].id.uuidString])
        let reopened = try await LocalRepository(folder: folder).load()
        XCTAssertEqual(reopened, data)
    }

    func testFailedTransactionRollsBackEarlierWritesAndDeletes() throws {
        let folder = folder(); defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let db = database(folder), original = ["a": Data([1]), "b": Data([2])]
        try db.apply(writes: original, deletes: [])
        // The DELETE fails after every INSERT has executed: all earlier writes must roll back.
        try db.execute("CREATE TRIGGER reject_delete BEFORE DELETE ON records BEGIN SELECT RAISE(ABORT, 'Failure'); END")
        XCTAssertThrowsError(try db.apply(writes: ["a": Data([3]), "c": Data([4])], deletes: ["b"]))
        XCTAssertEqual(try db.read(), original)
        try db.execute("DROP TRIGGER reject_delete")
        try db.apply(writes: ["a": Data([3]), "c": Data([4])], deletes: ["b"])
        XCTAssertEqual(try db.read(), ["a": Data([3]), "c": Data([4])])
    }

    func testDeletingPlanAndUndoKeepRecordOrderAndImages() async throws {
        let folder = folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder), original = try SeedCatalog.initialData()
        try await repository.save(original, revision: 1)
        var removed = original; removed.plans = []
        try await repository.save(removed, revision: 2)
        XCTAssertFalse(try database(folder).read().keys.contains { $0.hasPrefix("plans/") })
        try await repository.save(original, revision: 3)
        let reopened = try await LocalRepository(folder: folder).load()
        XCTAssertEqual(reopened, original)
    }

    func testRestoreWithoutPrecedingLoadRemovesObsoleteRecords() async throws {
        let folder = folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let original = try SeedCatalog.initialData()
        try await LocalRepository(folder: folder).save(original, revision: 1)
        var replacement = original; replacement.plans = []; replacement.notes = [DiaryNote(title: "Nuovo")]
        try await LocalRepository(folder: folder).save(replacement, revision: 1)
        let reopened = try await LocalRepository(folder: folder).load()
        XCTAssertEqual(reopened, replacement)
    }

    func testNewRevisionWithSameDataDoesNotCommit() async throws {
        let folder = folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder), original = try SeedCatalog.initialData()
        try await repository.save(original, revision: 1)
        let db = database(folder), version = try db.integer("PRAGMA data_version")
        try await repository.save(original, revision: 2)
        XCTAssertEqual(try db.integer("PRAGMA data_version"), version)
        let keys = await repository.lastWrittenKeys
        XCTAssertTrue(keys.isEmpty)
    }

    func testMissingRecordFailsWithoutReplacingDatabase() async throws {
        let folder = folder(); defer { try? FileManager.default.removeItem(at: folder) }
        try await LocalRepository(folder: folder).save(SeedCatalog.initialData(), revision: 1)
        let db = database(folder)
        try db.apply(writes: [:], deletes: ["week/0"])
        let before = try db.read()
        do { _ = try await LocalRepository(folder: folder).load(); XCTFail("Incomplete database accepted") } catch { }
        XCTAssertEqual(try db.read(), before)
    }

    func testSeparatedImageLegacyFormatMigratesAndKeepsPhotos() async throws {
        let folder = folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let original = try SeedCatalog.initialData()
        try await LocalRepository(folder: folder).save(original, revision: 1)
        let rows = try database(folder).read().mapValues { try JSONDecoder().decode(LocalRecord.self, from: $0) }
        let legacy = try RecordArchive.join(rows)
        // Move a v2 archive and its photos to a clean folder, like an installed older app.
        let destination = self.folder(); defer { try? FileManager.default.removeItem(at: destination) }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: folder.appendingPathComponent("images-v2"), to: destination.appendingPathComponent("images-v2"))
        let file = destination.appendingPathComponent("data-v1.json")
        try JSONEncoder().encode(legacy).write(to: file)
        let repository = LocalRepository(folder: destination)
        let loaded = try await repository.load()
        XCTAssertEqual(loaded, original)
        try await repository.save(loaded, revision: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let reopened = try await LocalRepository(folder: destination).load()
        XCTAssertEqual(reopened, original)
    }
}

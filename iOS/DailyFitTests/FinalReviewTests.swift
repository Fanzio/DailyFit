import XCTest
import Foundation
@testable import DailyFit

final class FinalReviewTests: XCTestCase {
    func testLocalImageArchiveIsSmallAndDoesNotRewriteUnchangedPhotos() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder)
        var data = try SeedCatalog.initialData()
        try await repository.save(data, revision: 1)
        let imageFolder = folder.appendingPathComponent("images-v2")
        let files = try FileManager.default.contentsOfDirectory(at: imageFolder, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 30)
        let marker = Date(timeIntervalSince1970: 946684800)
        for file in files { try FileManager.default.setAttributes([.modificationDate: marker], ofItemAtPath: file.path) }
        data.notes.append(DiaryNote(title: "Nuovo", body: "Appunto"))
        try await repository.save(data, revision: 2)
        data.notes.removeLast()
        try await repository.save(data, revision: 3)
        let metadata = try SQLiteRecords(url: folder.appendingPathComponent("records-v3.sqlite")).read()
        XCTAssertLessThan(metadata.values.reduce(0) { $0 + $1.count }, 100_000)
        for file in files {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual(attributes[.modificationDate] as? Date, marker)
        }
        let reopened = try await LocalRepository(folder: folder).load()
        XCTAssertEqual(reopened, data)
    }

    func testLegacyArchiveMigratesWithoutChangingPersonalData() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var data = try SeedCatalog.initialData()
        data.exercises[0].execution = "Descrizione personale"
        data.plans[0].days[0].entries[0].sets[0].load = 42.5
        data.notes.append(DiaryNote(title: "Conservare", body: "Appunto personale"))
        let file = folder.appendingPathComponent("data-v1.json")
        let oldBytes = try JSONEncoder().encode(data)
        try oldBytes.write(to: file)
        let repository = LocalRepository(folder: folder)
        let loaded = try await repository.load()
        XCTAssertEqual(loaded, data)
        XCTAssertEqual(try Data(contentsOf: file), oldBytes)
        try await repository.save(loaded, revision: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(try SQLiteRecords(url: folder.appendingPathComponent("records-v3.sqlite")).read().isEmpty)
        let reopened = try await LocalRepository(folder: folder).load()
        XCTAssertEqual(reopened, data)
    }

    func testChangedPhotoAndUndoRecreateRemovedImage() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder)
        let original = try SeedCatalog.initialData()
        try await repository.save(original, revision: 1)
        let oldPhoto = try XCTUnwrap(original.exercises[0].photo)
        let oldFile = folder.appendingPathComponent("images-v2").appendingPathComponent(LocalRepository.imageDigest(oldPhoto) + ".bin")
        var changed = original
        changed.exercises[0].photo = original.exercises[1].photo
        try await repository.save(changed, revision: 2)
        let reopened = try await LocalRepository(folder: folder).load()
        XCTAssertEqual(reopened, changed)
        // Explicit removal avoids depending on the scheduling of deferred cleanup.
        if FileManager.default.fileExists(atPath: oldFile.path) { try FileManager.default.removeItem(at: oldFile) }
        try await repository.save(original, revision: 3)
        XCTAssertEqual(try Data(contentsOf: oldFile), oldPhoto)
        let undone = try await LocalRepository(folder: folder).load()
        XCTAssertEqual(undone, original)
    }

    func testMissingLocalImagePreservesMetadataAndReportsLoadFailure() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder)
        let original = try SeedCatalog.initialData()
        try await repository.save(original, revision: 1)
        let database = SQLiteRecords(url: folder.appendingPathComponent("records-v3.sqlite")), bytes = try database.read()
        let photo = try XCTUnwrap(original.exercises[0].photo)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("images-v2").appendingPathComponent(LocalRepository.imageDigest(photo) + ".bin"))
        do { _ = try await LocalRepository(folder: folder).load(); XCTFail("Missing image accepted") } catch { }
        XCTAssertEqual(try database.read(), bytes)
    }

    func testTamperedLocalImageAndInvalidPathsAreRejected() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder)
        let original = try SeedCatalog.initialData()
        try await repository.save(original, revision: 1)
        let database = SQLiteRecords(url: folder.appendingPathComponent("records-v3.sqlite")), bytes = try database.read()
        let photo = try XCTUnwrap(original.exercises[0].photo)
        let imageFile = folder.appendingPathComponent("images-v2").appendingPathComponent(LocalRepository.imageDigest(photo) + ".bin")
        try Data([1, 2, 3]).write(to: imageFile)
        do { _ = try await LocalRepository(folder: folder).load(); XCTFail("Damaged image accepted") } catch { }
        XCTAssertEqual(try database.read(), bytes)
        try photo.write(to: imageFile)
        let key = "exercises/" + original.exercises[0].id.uuidString
        let row = try JSONDecoder().decode(LocalRecord.self, from: XCTUnwrap(bytes[key]))
        guard case let .exercise(exercise, _) = row else { return XCTFail("Missing exercise record") }
        let invalid = LocalRecord.exercise(exercise, ["photo": "../outside.bin"])
        try database.apply(writes: [key: JSONEncoder().encode(invalid)], deletes: [])
        do { _ = try await LocalRepository(folder: folder).load(); XCTFail("Invalid path accepted") } catch { }
    }

    func testPublicBackupIncludesPhotosAfterLocalImageMigration() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: destination) }
        let original = try SeedCatalog.initialData()
        try await LocalRepository(folder: folder).save(original, revision: 1)
        let reopened = try await LocalRepository(folder: folder).load()
        let backup = try BackupCodec.encode(reopened)
        try FileManager.default.removeItem(at: folder)
        let restored = try BackupCodec.decode(backup)
        XCTAssertEqual(restored.exercises, original.exercises)
        try await LocalRepository(folder: destination).save(restored, revision: 1)
        let transferred = try await LocalRepository(folder: destination).load()
        XCTAssertEqual(transferred.exercises, original.exercises)
        XCTAssertEqual(transferred.plans, original.plans)
    }

    func testLegacyLaunchAddsDefaultsOncePreservingRenamedPlanAndDeletions() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var legacy = SeedCatalog.makeData()
        legacy.defaultContentVersion = nil
        legacy.plans[0].name = "La mia scheda modificata"
        legacy.plans[0].days[0].entries[0].sets[0].load = 67.5
        legacy.exercises[0].execution = "Testo personale"
        legacy.exercises[1].archived = true
        let file = folder.appendingPathComponent("data-v1.json")
        try JSONEncoder().encode(legacy).write(to: file)
        let repository = LocalRepository(folder: folder)
        var loaded = try await repository.load()
        XCTAssertEqual(loaded.plans, legacy.plans)
        XCTAssertEqual(loaded.exercises, legacy.exercises)
        XCTAssertEqual(loaded.defaultContentVersion, SeedCatalog.contentVersion)
        loaded.plans = []
        loaded.exercises = []
        try await repository.save(loaded, revision: 1)
        let reopened = try await LocalRepository(folder: folder).load()
        XCTAssertEqual(reopened, loaded)
        XCTAssertTrue(reopened.plans.isEmpty); XCTAssertTrue(reopened.exercises.isEmpty)
    }

    @MainActor
    func testRestoringLegacyBackupKeepsChosenContentsAfterRelaunch() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(repository: LocalRepository(folder: folder))
        await store.load()
        var legacy = AppData()
        legacy.notes = [DiaryNote(title: "Unico contenuto", body: "Conserva questo backup")]
        let restored = await store.restoreBackup(try BackupCodec.decode(BackupCodec.encode(legacy)))
        XCTAssertTrue(restored)
        let reopened = try await LocalRepository(folder: folder).load()
        XCTAssertTrue(reopened.exercises.isEmpty); XCTAssertTrue(reopened.plans.isEmpty)
        XCTAssertEqual(reopened.notes, legacy.notes)
        XCTAssertEqual(reopened.defaultContentVersion, SeedCatalog.contentVersion)
    }

    func testSameRevisionDoesNotRewriteArchive() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder), original = SeedCatalog.makeData()
        try await repository.save(original, revision: 1)
        let database = SQLiteRecords(url: folder.appendingPathComponent("records-v3.sqlite"))
        let bytes = try database.read(), version = try database.integer("PRAGMA data_version")
        var changed = original; changed.notes = []
        try await repository.save(changed, revision: 1)
        XCTAssertEqual(try database.read(), bytes)
        XCTAssertEqual(try database.integer("PRAGMA data_version"), version)
    }

    @MainActor
    func testUnchangedEditKeepsUndoAndDoesNotSaveAgain() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(repository: LocalRepository(folder: folder))
        await store.load()
        XCTAssertTrue(store.delete(label: "Scheda") { $0.plans.removeAll() })
        await store.flush()
        let undoID = try XCTUnwrap(store.deletionUndo?.id)
        let database = SQLiteRecords(url: folder.appendingPathComponent("records-v3.sqlite"))
        let version = try database.integer("PRAGMA data_version")
        XCTAssertTrue(store.change { _ in })
        await store.flush()
        XCTAssertEqual(store.deletionUndo?.id, undoID)
        XCTAssertEqual(try database.integer("PRAGMA data_version"), version)
        store.discardDeletionUndo()
    }

    func testTimerHandlesExtremeDeadlinesWithoutIntegerOverflow() {
        var timer = RestTimer(entryID: UUID(), name: "Test", duration: 90, deadline: Date(timeIntervalSinceReferenceDate: 1e100))
        XCTAssertEqual(timer.remaining(), 3600)
        timer.deadline = Date(timeIntervalSinceReferenceDate: -1e100)
        XCTAssertEqual(timer.remaining(), 0)
        timer.deadline = nil; timer.pausedSeconds = Int.max
        XCTAssertEqual(timer.remaining(), 3600)
        timer.pausedSeconds = -1
        XCTAssertEqual(timer.remaining(), 0)
    }

    @MainActor
    func testInvalidNoteDoesNotReplaceSavedText() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(repository: LocalRepository(folder: folder))
        await store.load()
        var note = DiaryNote(title: "Appunto", body: "Testo salvato")
        XCTAssertTrue(store.saveNote(note))
        let original = store.data
        note.title = String(repeating: "a", count: 121)
        XCTAssertFalse(store.saveNote(note))
        XCTAssertEqual(store.data, original)
        XCTAssertNotNil(store.message)
        await store.flush()
    }

    func testBackupRejectsMismatchedFoodSnapshotIdentity() throws {
        var data = SeedCatalog.makeData()
        var snapshot = data.foods[0]; snapshot.id = UUID()
        data.week[0].meals[0].items = [MealItem(foodID: data.foods[0].id, quantity: 100, snapshot: snapshot)]
        XCTAssertThrowsError(try data.validate())
        XCTAssertThrowsError(try BackupCodec.encode(data))
    }
}

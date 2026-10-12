import XCTest
import Foundation
@testable import DailyFit

final class LazyImageTests: XCTestCase {
    private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    func testPhotoDownsamplingBoundsDecodedPixels() throws {
        let source = try XCTUnwrap(SeedCatalog.initialData().exercises[0].photo)
        let image = try XCTUnwrap(ImageProcessing.thumbnail(source, maxSize: 192)?.cgImage)
        XCTAssertLessThanOrEqual(max(image.width, image.height), 192)
        let jpeg = try ImageProcessing.importJPEG(source)
        XCTAssertLessThanOrEqual(jpeg.count, 2_000_000)
    }

    func testInvalidPhotoDoesNotDecodeOrImport() {
        let bytes = Data([1, 2, 3])
        XCTAssertNil(ImageProcessing.thumbnail(bytes, maxSize: 192))
        XCTAssertThrowsError(try ImageProcessing.importJPEG(bytes))
        let empty = Exercise(name: "Prova", muscle: "Petto", execution: "", photo: Data())
        XCTAssertThrowsError(try empty.validate())
    }

    func testLargeHistoryAndNoteEditOnlyWriteChangedNote() async throws {
        let folder = folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder)
        var data = try SeedCatalog.initialData()
        let start = try XCTUnwrap(Dates.fromKey("2020-01-01"))
        for i in 0..<1000 {
            let date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: i, to: start))
            data.dates[Dates.key(date)] = data.week[0]
        }
        data.notes = [DiaryNote(title: "Nota", body: "Prima")]
        var lazy = try await repository.save(data, revision: 1)
        lazy.notes[0].body = "Dopo"
        try await repository.save(lazy, revision: 2)
        let keys = await repository.lastWrittenKeys
        XCTAssertEqual(keys, ["notes/" + lazy.notes[0].id.uuidString])
        let reopened = try await repository.load(includingImages: false)
        XCTAssertEqual(reopened.dates.count, 1000)
        XCTAssertNil(reopened.exercises[0].photo)
    }

    func testNormalLoadContainsReferencesInsteadOfPhotoPayloads() async throws {
        let folder = folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let original = try SeedCatalog.initialData()
        try await LocalRepository(folder: folder).save(original, revision: 1)
        let repository = LocalRepository(folder: folder)
        let loaded = try await repository.load(includingImages: false)
        XCTAssertEqual(loaded.exercises.count, 15)
        XCTAssertTrue(loaded.exercises.allSatisfy { $0.photo == nil && $0.musclePhoto == nil && $0.photoFile != nil && $0.hasMusclePhoto })
        XCTAssertLessThan(try JSONEncoder().encode(loaded).count, 100_000)
        let picture = try await repository.imageBytes(XCTUnwrap(loaded.exercises[0].photoFile))
        XCTAssertEqual(picture, original.exercises[0].photo)
    }

    func testSaveNormalizesNewPhotosAndUndoRetainsReferencedFile() async throws {
        let folder = folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder)
        let normalized = try await repository.save(SeedCatalog.initialData(), revision: 1)
        XCTAssertNil(normalized.exercises[0].photo)
        let file = try XCTUnwrap(normalized.exercises[0].photoFile)
        var deleted = normalized; deleted.exercises[0].photoFile = nil
        try await repository.save(deleted, revision: 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("images-v2").appendingPathComponent(file).path))
        try await repository.save(normalized, revision: 3)
        let restored = try await repository.load(includingImages: false)
        XCTAssertEqual(restored, normalized)
    }

    func testLazySnapshotExportsPortableBackupWithAllImages() async throws {
        let folder = folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder), original = try SeedCatalog.initialData()
        let lazy = try await repository.save(original, revision: 1)
        let materialized = try await repository.materialize(lazy)
        let backup = try BackupCodec.encode(materialized)
        try FileManager.default.removeItem(at: folder)
        XCTAssertEqual(try BackupCodec.decode(backup), original)
    }

    func testPublicBackupRejectsLocalReferences() throws {
        var data = SeedCatalog.makeData()
        data.exercises[0].photoFile = String(repeating: "a", count: 64) + ".bin"
        XCTAssertThrowsError(try BackupCodec.encode(data))
        let forged = BackupEnvelope(format: "DailyFit", version: 1, exportedAt: Date(), data: data)
        XCTAssertThrowsError(try BackupCodec.decode(JSONEncoder().encode(forged)))
    }

    func testLazyAccessRejectsCorruptPhotoWithoutReplacingArchive() async throws {
        let folder = folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder)
        let lazy = try await repository.save(SeedCatalog.initialData(), revision: 1)
        let file = try XCTUnwrap(lazy.exercises[0].photoFile)
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("images-v2").appendingPathComponent(file))
        let loaded = try await repository.load(includingImages: false)
        XCTAssertEqual(loaded, lazy)
        do { _ = try await repository.imageBytes(file); XCTFail("Corrupt photo accepted") } catch { }
        do { _ = try await repository.materialize(loaded); XCTFail("Corrupt photo exported") } catch { }
    }

    func testUnusedImagesAreReclaimedAtNextColdLoad() async throws {
        let folder = folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder)
        var lazy = try await repository.save(SeedCatalog.initialData(), revision: 1)
        let file = try XCTUnwrap(lazy.exercises[0].photoFile)
        lazy.exercises[0].photoFile = nil
        try await repository.save(lazy, revision: 2)
        _ = try await LocalRepository(folder: folder).load(includingImages: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("images-v2").appendingPathComponent(file).path))
    }

    @MainActor func testAppStoreDoesNotRetainImagePayloadsAfterFlush() async throws {
        let folder = folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(repository: LocalRepository(folder: folder))
        await store.load()
        XCTAssertTrue(store.ready)
        XCTAssertTrue(store.data.exercises.allSatisfy { $0.photo == nil && $0.musclePhoto == nil })
        let snapshot = try await store.exportSnapshot(store.data)
        XCTAssertTrue(snapshot.exercises.allSatisfy { $0.photo != nil && $0.musclePhoto != nil })
        await store.flush()
    }
}

import XCTest
import UIKit
@testable import DailyFit

final class SeedImageTests: XCTestCase {
    private func included(_ name: String) -> Exercise {
        Exercise(name: name, muscle: "Petto", execution: "Descrizione inclusa", photo: Data([1]), musclePhoto: Data([2]))
    }

    func testExplicitCatalogImportPreservesPersonalDataAndIsRepeatable() throws {
        var data = AppData()
        let personal = Exercise(name: "Personale", muscle: "Petto", execution: "Le mie note", photo: Data([7]))
        data.exercises = [personal]
        data.plans = [TrainingPlan(name: "La mia scheda")]
        data.notes = [DiaryNote(title: "Appunto", body: "Da conservare")]
        let before = data
        let catalog = [included("Panca piana"), included("Squat")]
        XCTAssertEqual(try SeedCatalog.addMissingExercises(to: &data, catalog: catalog), 2)
        XCTAssertEqual(data.exercises.first, personal)
        XCTAssertEqual(data.plans, before.plans)
        XCTAssertEqual(data.notes, before.notes)
        XCTAssertEqual(data.foods, before.foods)
        XCTAssertEqual(data.exercises[1].photo, catalog[0].photo)
        XCTAssertEqual(data.exercises[1].musclePhoto, catalog[0].musclePhoto)
        let imported = data
        XCTAssertEqual(try SeedCatalog.addMissingExercises(to: &data, catalog: catalog), 0)
        XCTAssertEqual(data, imported)
    }

    func testExplicitCatalogImportKeepsEditedAndArchivedExercises() throws {
        var data = AppData()
        var existing = included("  PANCA   PIANA  ")
        existing.execution = "Testo modificato"
        existing.photo = nil
        existing.archived = true
        data.exercises = [existing]
        let before = data
        XCTAssertEqual(try SeedCatalog.addMissingExercises(to: &data, catalog: [included("Panca piana")]), 0)
        XCTAssertEqual(data, before)
    }

    func testExplicitCatalogImportWithMissingResourcesLeavesArchiveUnchanged() throws {
        var data = AppData()
        data.exercises = [included("Personale")]
        let before = data
        var missing = included("Squat")
        missing.musclePhoto = nil
        XCTAssertThrowsError(try SeedCatalog.addMissingExercises(to: &data, catalog: [included("Panca piana"), missing]))
        XCTAssertEqual(data, before)
        XCTAssertThrowsError(try SeedCatalog.addMissingExercises(to: &data, catalog: []))
        XCTAssertEqual(data, before)
    }

    func testBundledCatalogContainsFifteenExercisesAndThirtyReadableImages() throws {
        let data = SeedCatalog.makeData()
        XCTAssertEqual(data.exercises.count, 15)
        XCTAssertEqual(Set(data.exercises.map(\.name)).count, 15)
        for exercise in data.exercises {
            XCTAssertFalse(exercise.execution.isEmpty)
            for bytes in [exercise.photo, exercise.musclePhoto] {
                let bytes = try XCTUnwrap(bytes, "Immagine mancante: " + exercise.name)
                XCTAssertLessThanOrEqual(bytes.count, 2_000_000)
                let image = try XCTUnwrap(UIImage(data: bytes))
                XCTAssertEqual(image.size, CGSize(width: 1536, height: 1024))
            }
        }
        let backup = try BackupCodec.encode(data)
        XCTAssertLessThan(backup.count, 64_000_000)
        XCTAssertEqual(try BackupCodec.decode(backup), data)
        try data.validate()
    }

    func testLegacyExerciseWithoutMusclePhotoDecodesAndImagesAreIndependent() throws {
        var original = Exercise(name: "Personale", muscle: "Petto", execution: "", photo: Data([1, 2, 3]), musclePhoto: Data([4, 5, 6]))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "musclePhoto")
        let legacy = try JSONDecoder().decode(Exercise.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.photo, original.photo); XCTAssertNil(legacy.musclePhoto)
        let first = original.photo
        original.musclePhoto = nil
        XCTAssertEqual(original.photo, first)
        original.musclePhoto = Data(repeating: 0, count: 2_000_001)
        XCTAssertThrowsError(try original.validate())
    }

    func testExistingLocalCatalogIsNotReplacedByNewSeedImages() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder)
        var saved = SeedCatalog.makeData()
        saved.exercises = [Exercise(name: "Il mio esercizio", muscle: "Altro", execution: "Testo personale", photo: Data([7]), musclePhoto: Data([8]))]
        saved.plans = []
        try await repository.save(saved, revision: 1)
        let loaded = try await repository.load()
        XCTAssertEqual(loaded, saved)
        XCTAssertEqual(loaded.exercises.count, 1)
    }
}

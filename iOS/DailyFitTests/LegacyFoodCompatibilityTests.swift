import XCTest
import Foundation
@testable import DailyFit

final class LegacyFoodCompatibilityTests: XCTestCase {
    private func sample() -> AppData {
        var data = AppData()
        let food = Food(name: "Alimento precedente", unit: .ml,
                        nutrients: Nutrients(kcal: 46, protein: 3.5, fat: 1.5, carbs: 5))
        data.foods = [food, Food(name: "Alimento in grammi", nutrients: Nutrients(kcal: 100))]
        data.notes = [DiaryNote(title: "Nota da conservare", body: "Testo originale")]
        data.week[0].meals[0].items = [MealItem(foodID: food.id, quantity: 250)]
        data.week[1].meals[0].items = [MealItem(foodID: food.id, quantity: 150, snapshot: food)]
        data.dates["2026-10-05"] = data.week[0]
        data.dates["2026-10-06"] = data.week[1]
        return data
    }

    private func gramFood(_ data: AppData) -> Food {
        var food = data.foods[0]
        food.unit = .g
        food.nutrients = Nutrients(kcal: 50, protein: 4, fat: 2, carbs: 4)
        return food
    }

    func testCompatibilityValidationDoesNotReinterpretVolumes() throws {
        let data = sample(), before = try JSONEncoder().encode(data)
        XCTAssertNoThrow(try data.validate(allowLegacyFoodUnits: true))
        XCTAssertThrowsError(try data.validate())
        XCTAssertEqual(try JSONDecoder().decode(AppData.self, from: before), data)
        XCTAssertEqual(data.food(data.week[0].meals[0].items[0])?.unit, .ml)
        XCTAssertEqual(data.week[0].meals[0].items[0].quantity, 250)
    }

    func testCompatibilityStillRejectsInvalidQuantitiesAndNutrients() {
        var data = sample()
        data.week[0].meals[0].items[0].quantity = -1
        XCTAssertThrowsError(try data.validate(allowLegacyFoodUnits: true))
        data = sample(); data.foods[0].nutrients.kcal = .nan
        XCTAssertThrowsError(try data.validate(allowLegacyFoodUnits: true))
    }

    func testEditingNotePreservesExistingLegacyFoodsButRejectsNewVolumeFood() throws {
        let previous = sample()
        var next = previous; next.notes[0].body = "Nota aggiornata"
        XCTAssertNoThrow(try next.validate(changesFrom: previous))
        XCTAssertEqual(next.foods, previous.foods)
        next.foods.append(Food(name: "Nuovo volume vietato", unit: .ml, nutrients: Nutrients()))
        XCTAssertThrowsError(try next.validate(changesFrom: previous))
    }

    func testSavingGramCatalogFoodPreservesAllOriginalMealQuantitiesAndUnits() throws {
        let original = sample()
        var data = original
        try data.saveGramFood(gramFood(data))
        XCTAssertEqual(data.foods[0].unit, .g)
        for (before, after) in zip(original.week, data.week) {
            for (oldMeal, newMeal) in zip(before.meals, after.meals) {
                for (old, new) in zip(oldMeal.items, newMeal.items) {
                    XCTAssertEqual(old.quantity, new.quantity)
                    XCTAssertEqual(data.food(new), original.food(old))
                }
            }
        }
        for (key, day) in original.dates {
            XCTAssertEqual(data.dates[key]?.meals[0].items[0].quantity, day.meals[0].items[0].quantity)
            let item = try XCTUnwrap(data.dates[key]?.meals[0].items.first)
            XCTAssertEqual(data.food(item)?.unit, .ml)
        }
        XCTAssertNoThrow(try data.validate(changesFrom: original))
    }

    func testCorrectingOneBasePortionDoesNotChangeOtherDaysOrPersonalizedDates() throws {
        var data = sample()
        let food = gramFood(data)
        try data.saveGramFood(food)
        let before = data
        let date = try XCTUnwrap(Dates.fromKey("2026-10-05"))
        let meal = data.week[0].meals[0], item = meal.items[0]
        try data.correctLegacyPortion(date: date, base: true, mealID: meal.id, itemID: item.id, food: food, grams: 257)
        XCTAssertEqual(data.week[0].meals[0].items[0].quantity, 257)
        XCTAssertEqual(data.week[0].meals[0].items[0].snapshot, food)
        XCTAssertEqual(data.week[1], before.week[1])
        XCTAssertEqual(data.dates, before.dates)
        XCTAssertNoThrow(try data.validate(changesFrom: before))
    }

    func testCorrectingDateCreatesIndependentCopyWithoutChangingBase() throws {
        var data = sample()
        let food = gramFood(data)
        try data.saveGramFood(food)
        let before = data
        let date = try XCTUnwrap(Dates.fromKey("2026-10-12"))
        let meal = data.week[0].meals[0], item = meal.items[0]
        try data.correctLegacyPortion(date: date, base: false, mealID: meal.id, itemID: item.id, food: food, grams: 260)
        XCTAssertEqual(data.week, before.week)
        XCTAssertEqual(data.dates["2026-10-12"]?.meals[0].items[0].quantity, 260)
        XCTAssertEqual(data.dates["2026-10-12"]?.meals[0].items[0].snapshot?.unit, .g)
        XCTAssertEqual(data.dates["2026-10-05"], before.dates["2026-10-05"])
    }

    func testInvalidManualCorrectionLeavesDataUnchanged() throws {
        var data = sample()
        let before = data, date = try XCTUnwrap(Dates.fromKey("2026-10-05"))
        let meal = data.week[0].meals[0], item = meal.items[0]
        let oldFood = data.foods[0], reviewedFood = gramFood(data)
        XCTAssertThrowsError(try data.correctLegacyPortion(date: date, base: true, mealID: meal.id,
                            itemID: item.id, food: oldFood, grams: 250))
        XCTAssertEqual(data, before)
        XCTAssertThrowsError(try data.correctLegacyPortion(date: date, base: true, mealID: meal.id,
                            itemID: item.id, food: reviewedFood, grams: 0))
        XCTAssertEqual(data, before)
    }

    func testBackupAndExcelKeepOriginalVolumeLabelsUntilManualCorrection() throws {
        let original = sample()
        let decoded = try BackupCodec.decode(BackupCodec.encode(original))
        XCTAssertEqual(decoded, original)
        let sheets = try SpreadsheetExport.sheets(for: original)
        XCTAssertEqual(sheets.count, 11)
        XCTAssertTrue(original.hasLegacyFoodUnits)
    }

    @MainActor
    func testOpeningLegacyJSONAndFlushingDoesNotReplaceOrRewriteIt() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = sample(), bytes = try JSONEncoder().encode(original)
        let file = folder.appendingPathComponent("data-v1.json")
        try bytes.write(to: file)
        let store = AppStore(repository: LocalRepository(folder: folder))
        await store.load(); await store.flush()
        XCTAssertTrue(store.ready)
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.data, original)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertTrue(try SQLiteRecords(url: folder.appendingPathComponent("records-v3.sqlite")).read().isEmpty)
        XCTAssertTrue(store.saveNote(DiaryNote(title: "Aggiunta manuale")))
        await store.flush()
        let reopened = try await LocalRepository(folder: folder).load(includingImages: false)
        XCTAssertEqual(reopened.foods, original.foods)
        XCTAssertEqual(reopened.week, original.week)
        XCTAssertEqual(reopened.notes.count, 2)
    }

    @MainActor
    func testOpeningLegacySQLiteDoesNotChangeItsRecords() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = sample()
        let repository = LocalRepository(folder: folder)
        try await repository.save(original, revision: 1, allowLegacyFoodUnits: true)
        let db = SQLiteRecords(url: folder.appendingPathComponent("records-v3.sqlite"))
        let before = try db.read()
        let store = AppStore(repository: LocalRepository(folder: folder))
        await store.load(); await store.flush()
        XCTAssertTrue(store.ready)
        XCTAssertEqual(store.data, original)
        XCTAssertEqual(try db.read(), before)
    }

    func testLegacyImageEnvelopeCanBeOpenedWithoutDroppingVolumeData() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = sample(), envelope = LocalImageEnvelope(data: original, images: [:])
        let bytes = try JSONEncoder().encode(envelope)
        let file = folder.appendingPathComponent("data-v1.json")
        try bytes.write(to: file)
        let loaded = try await LocalRepository(folder: folder).load(includingImages: false)
        XCTAssertEqual(loaded, original)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testInvalidLegacyArchiveStillFailsWithoutReplacingData() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var invalid = sample(); invalid.week[0].meals[0].items[0].quantity = -10
        let bytes = try JSONEncoder().encode(invalid)
        let file = folder.appendingPathComponent("data-v1.json")
        try bytes.write(to: file)
        do { _ = try await LocalRepository(folder: folder).load(); XCTFail("Invalid archive accepted") } catch { }
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
}

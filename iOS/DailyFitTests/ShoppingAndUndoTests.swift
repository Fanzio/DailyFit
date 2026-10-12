import XCTest
import Foundation
@testable import DailyFit

final class ShoppingAndUndoTests: XCTestCase {
    private func sample() -> AppData {
        var data = SeedCatalog.makeData()
        let oats = data.foods[0].id
        for i in data.week.indices {
            data.week[i].meals[0].items = [MealItem(foodID: oats, quantity: 40)]
        }
        data.week[0].meals[1].items = [MealItem(foodID: oats, quantity: 20)]
        return data
    }

    func testShoppingSumsSevenBaseDaysByMealAndOverall() throws {
        let data = sample(), original = data
        let sections = ShoppingList.sections(for: data)
        XCTAssertEqual(sections.map(\.id), [.breakfast, .lunch])
        XCTAssertEqual(sections[0].items[0].quantity, 280)
        XCTAssertEqual(sections[1].items[0].quantity, 20)
        XCTAssertEqual(ShoppingList.totals(for: data)[0].quantity, 300)
        XCTAssertEqual(data, original)
    }

    func testShoppingIgnoresDateOverridesAndReflectsBaseEdits() throws {
        var data = sample()
        let monday = Dates.fromKey("2026-10-05")!
        data.editDiet(monday, base: false) { $0.meals[0].items[0].quantity = 900 }
        XCTAssertEqual(ShoppingList.totals(for: data)[0].quantity, 300)
        data.week[0].meals[0].items[0].quantity = 40.25
        XCTAssertEqual(ShoppingList.totals(for: data)[0].quantity, 300.25, accuracy: 0.00001)
        XCTAssertEqual(data.diet(monday, base: false).meals[0].items[0].quantity, 900)
    }

    func testShoppingSeparatesCatalogIdentitiesAndIncludesArchivedFoods() throws {
        var data = SeedCatalog.makeData()
        let grams = Food(name: "Latte", unit: .g, nutrients: Nutrients())
        var archived = Food(name: "Latte", nutrients: Nutrients())
        archived.archived = true
        data.foods = [grams, archived]
        data.week[0].meals[0].items = [MealItem(foodID: grams.id, quantity: 100), MealItem(foodID: archived.id, quantity: 250), MealItem(foodID: grams.id, quantity: 75, snapshot: grams)]
        try data.validate()
        let totals = ShoppingList.totals(for: data)
        XCTAssertEqual(totals.count, 2)
        XCTAssertEqual(totals.first { $0.id.foodID == grams.id }?.quantity, 175)
        XCTAssertEqual(totals.first { $0.id.foodID == archived.id }?.quantity, 250)
        XCTAssertTrue(totals.allSatisfy { $0.unit == .g })
    }

    func testShoppingSnacksAreOptionalAndCustomNamesAreKept() throws {
        var data = SeedCatalog.makeData()
        XCTAssertTrue(ShoppingList.sections(for: data).isEmpty)
        data.week[0].meals.append(Meal(name: "Merenda", isSnack: true, items: [MealItem(foodID: data.foods[0].id, quantity: 35)]))
        data.week[1].meals.append(Meal(name: "Dopo allenamento", isSnack: true, items: [MealItem(foodID: data.foods[0].id, quantity: 25)]))
        let sections = ShoppingList.sections(for: data)
        XCTAssertEqual(sections.map(\.id), [.snacks])
        XCTAssertEqual(sections[0].items[0].quantity, 60)
        XCTAssertEqual(data.week[0].meals.last?.name, "Merenda")
        data.week[2].meals.append(Meal(name: "Pasto speciale", items: [MealItem(foodID: data.foods[1].id, quantity: 50)]))
        XCTAssertEqual(ShoppingList.sections(for: data).map(\.id), [.snacks, .other])
    }

    func testReorderingBasePreservesQuantitiesTotalsAndPersonalDates() throws {
        var data = sample()
        let date = Dates.fromKey("2026-10-05")!
        data.week[0].meals[0].items.append(MealItem(foodID: data.foods[1].id, quantity: 125))
        data.editDiet(date, base: false) { $0.meals[0].items[0].quantity = 80 }
        let before = data.week[0], personal = data.diet(date, base: false)
        let shopping = ShoppingList.totals(for: data)
        try data.moveMealItem(date: date, base: true, mealID: before.meals[0].id, itemID: before.meals[0].items[1].id, offset: -1)
        XCTAssertEqual(data.week[0].meals[0].items, Array(before.meals[0].items.reversed()))
        XCTAssertEqual(data.totals(data.week[0]), data.totals(before))
        XCTAssertEqual(data.diet(date, base: false), personal)
        XCTAssertEqual(ShoppingList.totals(for: data), shopping)
        try data.validate()
    }

    func testReorderingOneDateDoesNotChangeBaseOrFollowingWeek() throws {
        var data = sample()
        let date = Dates.fromKey("2026-10-05")!
        data.week[0].meals[0].items.append(MealItem(foodID: data.foods[1].id, quantity: 125))
        let base = data.week[0], meal = base.meals[0]
        try data.moveMealItem(date: date, base: false, mealID: meal.id, itemID: meal.items[0].id, offset: 1)
        XCTAssertEqual(data.diet(date, base: false).meals[0].items.map(\.id), meal.items.reversed().map(\.id))
        XCTAssertEqual(data.week[0], base)
        XCTAssertEqual(data.diet(Dates.shifting(date, days: 7), base: false), base)
        XCTAssertTrue(data.diet(date, base: false).meals[0].items.allSatisfy { $0.snapshot != nil })
    }

    func testInvalidReorderingDoesNotCreateAPersonalizedDate() throws {
        var data = sample()
        let original = data, date = Dates.fromKey("2026-10-05")!, meal = data.week[0].meals[0]
        XCTAssertThrowsError(try data.moveMealItem(date: date, base: false, mealID: meal.id, itemID: meal.items[0].id, offset: -1))
        XCTAssertThrowsError(try data.moveMealItem(date: date, base: false, mealID: UUID(), itemID: meal.items[0].id, offset: 1))
        XCTAssertThrowsError(try data.moveMealItem(date: date, base: false, mealID: meal.id, itemID: UUID(), offset: 1))
        XCTAssertEqual(data, original)
    }

    @MainActor
    func testUndoDeletionRestoresNestedPlanAndPersists() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder), store = AppStore(repository: LocalRepository(folder: folder))
        await store.load()
        let entry = TrainingEntry(exerciseID: store.data.exercises[0].id)
        let plan = TrainingPlan(name: "Scheda", days: [TrainingDay(name: "A", entries: [entry])])
        XCTAssertTrue(store.change { $0.plans = [plan] })
        XCTAssertTrue(store.delete(label: "Scheda eliminata") { $0.plans.removeAll() })
        XCTAssertTrue(store.data.plans.isEmpty)
        XCTAssertTrue(store.undoLastDeletion())
        XCTAssertEqual(store.data.plans, [plan]); XCTAssertNil(store.deletionUndo)
        await store.flush()
        let loaded = try await repository.load()
        XCTAssertEqual(loaded.plans, [plan])
    }

    @MainActor
    func testUndoLatestDeletionOnlyAndExpiration() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(repository: LocalRepository(folder: folder)); await store.load()
        let first = DiaryNote(title: "Prima"), second = DiaryNote(title: "Seconda")
        store.change { $0.notes = [first, second] }
        let now = Date()
        store.delete(label: "Prima", at: now) { $0.notes.removeAll { $0.id == first.id } }
        store.delete(label: "Seconda", at: now) { $0.notes.removeAll { $0.id == second.id } }
        XCTAssertTrue(store.undoLastDeletion(at: now.addingTimeInterval(1)))
        XCTAssertEqual(store.data.notes, [second])
        store.delete(label: "Seconda", at: now) { $0.notes.removeAll() }
        XCTAssertFalse(store.undoLastDeletion(at: now.addingTimeInterval(15)))
        XCTAssertTrue(store.data.notes.isEmpty); XCTAssertNil(store.deletionUndo)
        await store.flush()
    }

    @MainActor
    func testUndoDoesNotOverwriteLaterEditsOrRestartTimers() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(repository: LocalRepository(folder: folder)); await store.load()
        let entry = TrainingEntry(exerciseID: store.data.exercises[0].id)
        let timer = RestTimer(entryID: entry.id, name: "Test", duration: 90, deadline: Date().addingTimeInterval(90))
        store.change { $0.plans = [TrainingPlan(name: "A", days: [TrainingDay(name: "A", entries: [entry])])]; $0.notes = [DiaryNote(title: "Nota")] }
        store.delete(label: "Nota") { $0.notes.removeAll() }
        store.change { $0.timer = timer }
        XCTAssertNotNil(store.deletionUndo)
        XCTAssertTrue(store.undoLastDeletion()); XCTAssertEqual(store.data.timer, timer)
        store.change { $0.timer = nil }
        store.delete(label: "Scheda") { $0.plans.removeAll() }
        XCTAssertTrue(store.undoLastDeletion()); XCTAssertNil(store.data.timer)
        store.delete(label: "Nota") { $0.notes.removeAll() }
        store.change { $0.foods[0].name = "Nome aggiornato" }
        XCTAssertNil(store.deletionUndo); XCTAssertFalse(store.undoLastDeletion())
        XCTAssertEqual(store.data.foods[0].name, "Nome aggiornato")
        await store.flush()
    }

    @MainActor
    func testUndoFoodRemovalRestoresDateAndCatalogState() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(repository: LocalRepository(folder: folder)); await store.load()
        store.change { $0 = sample() }
        let date = Dates.fromKey("2026-10-05")!, original = store.data
        store.delete(label: "Cibo") { $0.editDiet(date, base: false) { $0.meals[0].items.removeAll() } }
        XCTAssertNotNil(store.data.dates[Dates.key(date)])
        XCTAssertTrue(store.undoLastDeletion()); XCTAssertEqual(store.data, original)
        store.delete(label: "Catalogo") { $0.foods[0].archived = true }
        XCTAssertTrue(store.undoLastDeletion()); XCTAssertFalse(store.data.foods[0].archived)
        await store.flush()
    }

    @MainActor
    func testRestoreBackupAndExplicitDismissClearDeletionUndo() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(repository: LocalRepository(folder: folder)); await store.load()
        store.delete(label: "Catalogo") { $0.foods[0].archived = true }
        store.discardDeletionUndo()
        XCTAssertFalse(store.undoLastDeletion())
        store.delete(label: "Catalogo") { $0.foods[1].archived = true }
        let imported = sample()
        let success = await store.restoreBackup(imported)
        XCTAssertTrue(success); XCTAssertNil(store.deletionUndo)
        XCTAssertFalse(store.undoLastDeletion())
        let exported = try await store.exportSnapshot(store.data)
        XCTAssertEqual(exported, imported)
        await store.flush()
    }
}

import XCTest
@testable import DailyFit

final class IncrementalValidationTests: XCTestCase {
    private func rejected(_ next: AppData, previous: AppData, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try next.validate(), file: file, line: line)
        XCTAssertThrowsError(try next.validate(changesFrom: previous), file: file, line: line)
    }

    func testChangedFieldsKeepFullValidationGuarantees() throws {
        let previous = SeedCatalog.makeData()
        try previous.validate()
        let edits: [(inout AppData) -> Void] = [
            { $0.exercises[0].video = "javascript:alert(1)" },
            { $0.foods[0].unit = .ml },
            { $0.foods[0].nutrients.kcal = -1 },
            { $0.plans[0].days[0].entries[0].rest = 0 },
            { $0.plans[0].days[0].entries[0].sets[0].load = -1 },
            { $0.plans[0].days[0].entries[0].exerciseID = UUID() },
            { $0.foods.append($0.foods[0]) },
            { $0.chatLink = "https://untrusted.example/c/chat" },
            { $0.notes.append(DiaryNote(title: String(repeating: "x", count: 121))) },
            { $0.dates["2026-02-30"] = $0.week[0] }
        ]
        for edit in edits {
            var next = previous
            edit(&next)
            rejected(next, previous: previous)
        }
    }

    func testDeletedExerciseRechecksUnchangedEntries() throws {
        let previous = SeedCatalog.makeData()
        var next = previous
        let id = next.plans[0].days[0].entries[0].exerciseID
        next.exercises.removeAll { $0.id == id }
        rejected(next, previous: previous)
    }

    func testDeletingExerciseAndReferencesTogetherIsValid() throws {
        let previous = SeedCatalog.makeData()
        var next = previous
        let id = next.plans[0].days[0].entries[0].exerciseID
        next.exercises.removeAll { $0.id == id }
        for p in next.plans.indices {
            for d in next.plans[p].days.indices {
                next.plans[p].days[d].entries.removeAll { $0.exerciseID == id }
            }
        }
        XCTAssertNoThrow(try next.validate())
        XCTAssertNoThrow(try next.validate(changesFrom: previous))
    }

    func testDeletedFoodRechecksUnchangedMeals() throws {
        var previous = SeedCatalog.makeData()
        previous.week[0].meals[0].items = [MealItem(foodID: previous.foods[0].id, quantity: 100)]
        try previous.validate()
        var next = previous
        next.foods.removeFirst()
        rejected(next, previous: previous)
    }

    func testIndependentFoodSnapshotSurvivesCatalogRemoval() throws {
        var previous = SeedCatalog.makeData()
        let food = previous.foods[0]
        previous.week[0].meals[0].items = [MealItem(foodID: food.id, quantity: 100, snapshot: food)]
        try previous.validate()
        var next = previous
        next.foods.removeFirst()
        XCTAssertNoThrow(try next.validate())
        XCTAssertNoThrow(try next.validate(changesFrom: previous))
        next.week[0].meals[0].items[0].snapshot?.unit = .ml
        rejected(next, previous: previous)
    }

    func testWeightChangeRechecksUnchangedGoals() throws {
        var previous = SeedCatalog.makeData()
        previous.bodyWeight = 70
        previous.week[0].goals.proteinPerKg = 2
        try previous.validate()
        var next = previous
        next.bodyWeight = nil
        rejected(next, previous: previous)
    }

    func testChangedDateAndTimerAreValidated() throws {
        var previous = SeedCatalog.makeData()
        previous.timer = RestTimer(entryID: previous.plans[0].days[0].entries[0].id, name: "Recupero", duration: 90)
        try previous.validate()
        var next = previous
        var day = next.week[0]
        day.meals[0].items = [MealItem(foodID: next.foods[0].id, quantity: -1)]
        next.dates["2026-10-05"] = day
        rejected(next, previous: previous)
        next = previous
        next.timer?.duration = 0
        rejected(next, previous: previous)
        next = previous
        next.plans[0].days[0].entries.removeFirst()
        rejected(next, previous: previous)
    }

    func testSequentialEditsAndReordersRemainValid() throws {
        var previous = SeedCatalog.makeData()
        for i in 0..<40 {
            var next = previous
            next.plans[0].days[0].entries[0].sets[0].load = Double(i) / 2
            next.foods.swapAt(0, 1)
            XCTAssertNoThrow(try next.validate())
            XCTAssertNoThrow(try next.validate(changesFrom: previous))
            previous = next
        }
    }

    func testRepositoryRejectsInvalidEditAfterSuccessfulSave() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder)
        let original = SeedCatalog.makeData()
        try await repository.save(original, revision: 1)
        var invalid = original
        invalid.plans[0].days[0].entries[0].sets[0].load = -1
        do {
            try await repository.save(invalid, revision: 2)
            XCTFail("Invalid incremental save should fail")
        } catch { }
        let loaded = try await repository.load()
        XCTAssertEqual(loaded, original)
    }
}

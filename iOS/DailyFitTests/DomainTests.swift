import XCTest
@testable import DailyFit

final class DomainTests: XCTestCase {
    func testIndependentGoalsAcceptMismatchedCalories() throws {
        let goals = Goals(kcal: 500, proteinPerKg: 2, fatPerKg: 0.8, carbsPerKg: 3)
        let target = try goals.targets(weight: 70)
        XCTAssertEqual(target.kcal, 500)
        XCTAssertEqual(target.protein, 140); XCTAssertEqual(target.fat, 56); XCTAssertEqual(target.carbs, 210)
        XCTAssertNotEqual(4 * target.protein! + 9 * target.fat! + 4 * target.carbs!, target.kcal!)
        var changed = goals; changed.kcal = 5000
        XCTAssertEqual(try changed.targets(weight: 70).carbs, target.carbs)
        changed.proteinPerKg = 5
        XCTAssertEqual(try changed.targets(weight: 70).carbs, target.carbs)
        var data = SeedCatalog.makeData(); data.bodyWeight = 70; data.week[0].goals = goals
        try data.validate()
    }
    func testPartialGoalsAndInvalidNumbers() throws {
        XCTAssertNoThrow(try Goals(kcal: 500, proteinPerKg: 2).targets(weight: 70))
        XCTAssertNoThrow(try Goals(kcal: 1000, proteinPerKg: 2, fatPerKg: 1).targets(weight: 70))
        XCTAssertNoThrow(try Goals(kcal: 60000, proteinPerKg: 101, fatPerKg: 101, carbsPerKg: 101).targets(weight: 70))
        XCTAssertThrowsError(try Goals(proteinPerKg: 2).targets(weight: nil))
        XCTAssertThrowsError(try Goals(carbsPerKg: 2).targets(weight: nil))
        XCTAssertThrowsError(try Goals(kcal: -1).targets(weight: 70))
        XCTAssertThrowsError(try Goals(carbsPerKg: .nan).targets(weight: 70))
        XCTAssertThrowsError(try Goals(fatPerKg: .infinity).targets(weight: 70))
        XCTAssertThrowsError(try Goals(carbsPerKg: .greatestFiniteMagnitude).targets(weight: 70))
        XCTAssertEqual(try Goals(kcal: 2200).targets(weight: nil).kcal, 2200)
        XCTAssertNil(try Goals(kcal: 2200, proteinPerKg: 2).targets(weight: 70).carbs)
        XCTAssertNil(try Goals(kcal: 560, proteinPerKg: 2, fatPerKg: 0).targets(weight: 70).carbs)
        XCTAssertEqual(try Goals(carbsPerKg: 0).targets(weight: 70).carbs, 0)
        XCTAssertEqual(try Goals(carbsPerKg: 3).targets(weight: 70).carbs, 210)
    }
    func testEmptyCarbsRemainEmptyAfterRoundTrip() throws {
        let original = Goals(kcal: 2200, proteinPerKg: 2, fatPerKg: 0.8)
        var loaded = try JSONDecoder().decode(Goals.self, from: JSONEncoder().encode(original))
        loaded.migrateLegacyCarbs(weight: 70)
        XCTAssertEqual(loaded, original)
        XCTAssertNil(try loaded.targets(weight: 70).carbs)
    }
    func testDecimalInputAndURLs() throws {
        XCTAssertEqual(try Input.decimal("0,8", label: "Numero", range: 0...10), 0.8)
        for value in ["", "-1", "nan", "1e3", "0x10", "1,2,3"] { XCTAssertThrowsError(try Input.decimal(value, label: "Numero", range: 0...1000)) }
        XCTAssertEqual(try Input.chatURL("").absoluteString, "https://chatgpt.com/")
        XCTAssertNoThrow(try Input.chatURL("https://chatgpt.com/c/1234-abcd"))
        for link in ["javascript:alert(1)", "https://chatgpt.com.evil.org/c/123", "https://chatgpt.com/share/123", "https://user:pass@chatgpt.com/c/123", "https://chatgpt.com/c/123?prompt=secret"] { XCTAssertThrowsError(try Input.chatURL(link)) }
    }
    func testFoodUnitsAndLabelCalories() {
        let n = Nutrients(kcal: 46, protein: 3.5, fat: 1.5, carbs: 5)
        XCTAssertEqual(n.scaled(2.5).kcal, 115)
        XCTAssertNotEqual(n.kcal, 4 * n.protein + 9 * n.fat + 4 * n.carbs)
        let liquid = Food(name: "Esempio 100 g", nutrients: n)
        XCTAssertNoThrow(try liquid.validate())
        XCTAssertEqual(liquid.nutrients.scaled(250 / 100).protein, 8.75)
    }
    func testFoodValidationOnlyAcceptsGrams() throws {
        let data = SeedCatalog.makeData()
        XCTAssertTrue(data.foods.allSatisfy { $0.unit == .g })
        var food = data.foods[0]
        food.unit = .ml
        XCTAssertThrowsError(try food.validate())
        food.unit = .g
        XCTAssertNoThrow(try food.validate())
    }
    func testVolumeArchiveRejectedWithoutReinterpretation() throws {
        var data = SeedCatalog.makeData()
        data.foods[0].unit = .ml
        let bytes = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(AppData.self, from: bytes)
        XCTAssertThrowsError(try decoded.validate())
        XCTAssertEqual(decoded.foods[0].unit, .ml)
        XCTAssertEqual(data.foods[0].unit, .ml)
    }
    func testVolumeSnapshotsRejectedInBaseAndDates() throws {
        var data = SeedCatalog.makeData()
        var food = data.foods[0]
        food.unit = .ml
        let item = MealItem(foodID: food.id, quantity: 125, snapshot: food)
        data.week[0].meals[0].items = [item]
        XCTAssertThrowsError(try data.validate())
        data.week[0].meals[0].items = []
        var day = data.week[0]
        day.meals[0].items = [item]
        data.dates["2026-10-05"] = day
        XCTAssertThrowsError(try data.validate())
        XCTAssertEqual(data.dates["2026-10-05"]?.meals[0].items[0].quantity, 125)
    }
    func testDateChangesNeverChangeBaseOrFollowingWeek() throws {
        var data = SeedCatalog.makeData()
        let date = Dates.calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12))!
        let f = data.foods[0]
        data.bodyWeight = 70
        data.week[0].goals = Goals(kcal: 2200, proteinPerKg: 2, fatPerKg: 0.8, carbsPerKg: 3)
        data.week[0].meals[0].items = [MealItem(foodID: f.id, quantity: 100)]
        let original = data.week
        data.editDiet(date, base: false) { $0.meals[0].items[0].quantity = 200 }
        XCTAssertEqual(data.week, original)
        XCTAssertEqual(data.totals(data.diet(date, base: false)).kcal, 734)
        XCTAssertEqual(data.totals(data.diet(Dates.shifting(date, days: 7), base: false)).kcal, 367)
        data.foods[0].nutrients.kcal = 400; data.bodyWeight = 80; data.week[0].goals.kcal = 2400
        XCTAssertEqual(data.totals(data.diet(date, base: false)).kcal, 734)
        XCTAssertEqual(try data.targets(date, base: false).protein, 160)
        XCTAssertEqual(try data.targets(date, base: false).kcal, 2400)
        XCTAssertEqual(try data.targets(date, base: false).carbs, 240)
        XCTAssertEqual(try data.targets(Dates.shifting(date, days: 7), base: false).protein, 160)
        XCTAssertEqual(try data.targets(Dates.shifting(date, days: 7), base: false).carbs, 240)
        data.dates.removeValue(forKey: Dates.key(date))
        XCTAssertEqual(data.totals(data.diet(date, base: false)).kcal, 400)
        try data.validate()
    }
    func testDeletionFromCatalogPreservesMeals() throws {
        var data = SeedCatalog.makeData()
        let foodID = data.foods[0].id
        data.week[0].meals[0].items = [MealItem(foodID: foodID, quantity: 100)]
        data.foods[0].archived = true
        XCTAssertEqual(data.totals(data.week[0]).kcal, 367)
        try data.validate()
    }
    func testTrainingSetsAreIndependentValueCopies() throws {
        var data = SeedCatalog.makeData()
        let exerciseID = data.exercises[0].id
        data.plans = [TrainingPlan(name: "Scheda", days: [TrainingDay(name: "A", entries: [TrainingEntry(exerciseID: exerciseID)]), TrainingDay(name: "B", entries: [TrainingEntry(exerciseID: exerciseID)])])]
        data.plans[0].days[0].entries[0].sets[0].load = 55
        XCTAssertEqual(data.plans[0].days[1].entries[0].sets[0].load, 0)
        data.exercises[0].archived = true
        try data.validate()
    }
    func testTimerAcrossSuspensionPauseAndResume() {
        let now = Date(timeIntervalSince1970: 1000)
        var timer = RestTimer(entryID: UUID(), name: "Panca", duration: 90, deadline: now.addingTimeInterval(90))
        XCTAssertEqual(timer.remaining(at: now.addingTimeInterval(45)), 45)
        timer.pause(at: now.addingTimeInterval(45))
        XCTAssertEqual(timer.remaining(at: now.addingTimeInterval(600)), 45)
        timer.resume(at: now.addingTimeInterval(600))
        XCTAssertEqual(timer.remaining(at: now.addingTimeInterval(630)), 15)
        XCTAssertEqual(timer.remaining(at: now.addingTimeInterval(700)), 0)
    }
    func testWeekAndYearBoundaries() {
        let date = Dates.calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 12))!
        XCTAssertEqual(Dates.key(Dates.shifting(date, days: 7)), "2027-01-07")
        XCTAssertEqual(Dates.key(Dates.inWeek(Dates.shifting(date, days: 7), weekday: 0)), "2027-01-04")
        XCTAssertNil(Dates.fromKey("2027-02-30"))
        XCTAssertNotNil(Dates.fromKey("2028-02-29"))
    }
    func testSeedsAndCodableRoundTrip() throws {
        let data = SeedCatalog.makeData()
        XCTAssertFalse(data.exercises.isEmpty); XCTAssertEqual(data.foods.count, 6)
        XCTAssertEqual(data.week.count, 7)
        XCTAssertTrue(data.week.allSatisfy { $0.meals.count == 3 && !$0.meals.contains { $0.isSnack } })
        try data.validate()
        let encoded = try JSONEncoder().encode(data)
        XCTAssertEqual(try JSONDecoder().decode(AppData.self, from: encoded), data)
    }
    func testRepositoryRoundTripAndStaleWrite() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder)
        var first = SeedCatalog.makeData(); first.notes = [DiaryNote(title: "Persistente", body: "60 kg")]
        try await repository.save(first, revision: 2)
        var stale = first; stale.notes = []
        try await repository.save(stale, revision: 1)
        let loaded = try await repository.load()
        XCTAssertEqual(loaded, first)
        let excluded = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        XCTAssertEqual(excluded, true)
    }
    func testLegacyArchiveMigratesCarbsWithEachWeight() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let date = Dates.fromKey("2026-09-28")!
        var data = SeedCatalog.makeData(); data.bodyWeight = 70
        data.week[0].goals = Goals(kcal: 2200, proteinPerKg: 2, fatPerKg: 0.8)
        data.editDiet(date, base: false) { $0.weight = 60 }
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as? [String: Any])
        func oldDay(_ day: [String: Any]) -> [String: Any] {
            var copy = day
            var goals = copy["goals"] as! [String: Any]
            goals.removeValue(forKey: "carbsPerKg"); copy["goals"] = goals
            return copy
        }
        json["week"] = (json["week"] as! [[String: Any]]).map(oldDay)
        json["dates"] = (json["dates"] as! [String: [String: Any]]).mapValues(oldDay)
        try JSONSerialization.data(withJSONObject: json).write(to: folder.appendingPathComponent("data-v1.json"))
        let repository = LocalRepository(folder: folder)
        var loaded = try await repository.load()
        XCTAssertEqual(try loaded.targets(date, base: true).carbs!, 284, accuracy: 0.000001)
        XCTAssertEqual(try loaded.targets(date, base: false).carbs!, 284, accuracy: 0.000001)
        let savedDay = try XCTUnwrap(loaded.dates[Dates.key(date)])
        XCTAssertEqual(try savedDay.goals.targets(weight: savedDay.weight).carbs!, 322, accuracy: 0.000001)
        loaded.week[0].goals.kcal = 500
        XCTAssertEqual(try loaded.targets(date, base: true).carbs!, 284, accuracy: 0.000001)
        loaded.migrateLegacyGoals()
        try await repository.save(loaded, revision: 1)
        let reloaded = try await repository.load()
        XCTAssertEqual(reloaded, loaded)
        XCTAssertEqual(try reloaded.targets(date, base: true).carbs!, 284, accuracy: 0.000001)
        XCTAssertEqual(reloaded.plans, data.plans); XCTAssertEqual(reloaded.exercises, data.exercises)
    }
    func testCorruptArchiveIsNotOverwrittenOnLoad() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("data-v1.json")
        let broken = Data("{not-json}".utf8); try broken.write(to: file)
        let repository = LocalRepository(folder: folder)
        do { _ = try await repository.load(); XCTFail("Archivio corrotto accettato") } catch { }
        XCTAssertEqual(try Data(contentsOf: file), broken)
    }
}

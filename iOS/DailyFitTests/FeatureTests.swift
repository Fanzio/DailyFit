import XCTest
import Foundation
@testable import DailyFit

final class FeatureTests: XCTestCase {
    private func sample() -> AppData {
        var data = SeedCatalog.makeData()
        data.setBaseGoals(Goals(kcal: 500, proteinPerKg: 2, fatPerKg: 0.8, carbsPerKg: 3), weight: 70)
        data.keepScreenAwake = true
        data.exercises[0].photo = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jV1sAAAAASUVORK5CYII=")!
        let entry = TrainingEntry(exerciseID: data.exercises[0].id, sets: [TrainingSet(reps: 10, load: 40), TrainingSet(reps: 8, load: 45)], rest: 90)
        data.plans = [TrainingPlan(name: "Forza", days: [TrainingDay(name: "A", entries: [entry]), TrainingDay(name: "Vuoto")])]
        data.week[0].meals[0].items = [MealItem(foodID: data.foods[0].id, quantity: 100)]
        data.notes = [DiaryNote(title: "=SUM(1;2)", body: "Prima riga\nSeconda & <ultima> 🏋️")]
        return data
    }

    func testBaseGoalsApplyToAllDatesAndPersonalMeals() throws {
        var data = sample()
        let monday = Dates.fromKey("2026-10-05")!
        data.editDiet(monday, base: false) { $0.meals[0].items[0].quantity = 200 }
        let personalMeals = data.diet(monday, base: false).meals
        data.setBaseGoals(Goals(kcal: 100, proteinPerKg: 3, fatPerKg: 1, carbsPerKg: 4), weight: 80)
        let expected = Targets(kcal: 100, protein: 240, fat: 80, carbs: 320)
        for offset in 0..<21 {
            let date = Dates.shifting(monday, days: offset)
            XCTAssertEqual(try data.targets(date, base: true), expected)
            XCTAssertEqual(try data.targets(date, base: false), expected)
        }
        XCTAssertEqual(data.diet(monday, base: false).meals, personalMeals)
        try data.validate()
    }

    func testPlanDuplicateCreatesIndependentNestedIDs() throws {
        var data = sample()
        let original = data.plans[0]
        try data.duplicatePlan(original.id, name: "Copia")
        let copy = data.plans[1]
        XCTAssertNotEqual(copy.id, original.id)
        for i in original.days.indices {
            XCTAssertNotEqual(copy.days[i].id, original.days[i].id)
            for e in original.days[i].entries.indices {
                let a = original.days[i].entries[e], b = copy.days[i].entries[e]
                XCTAssertNotEqual(a.id, b.id); XCTAssertEqual(a.exerciseID, b.exerciseID)
                XCTAssertEqual(a.rest, b.rest)
                XCTAssertTrue(Set(a.sets.map(\.id)).isDisjoint(with: Set(b.sets.map(\.id))))
            }
        }
        data.plans[1].days[0].entries[0].sets[0].load = 100
        XCTAssertEqual(data.plans[0], original)
        try data.validate()
    }

    func testDayDuplicateDoesNotCopyActiveTimer() throws {
        var data = sample()
        let original = data.plans[0].days[0], entry = original.entries[0]
        data.timer = RestTimer(entryID: entry.id, name: "Panca", duration: 90, deadline: Date().addingTimeInterval(90))
        let timer = data.timer
        try data.duplicateDay(planID: data.plans[0].id, dayID: original.id, name: "B")
        let copy = data.plans[0].days[2]
        XCTAssertNotEqual(copy.id, original.id); XCTAssertNotEqual(copy.entries[0].id, entry.id)
        XCTAssertEqual(copy.entries[0].sets.map(\.load), entry.sets.map(\.load))
        XCTAssertEqual(data.timer, timer)
        data.plans[0].days[2].entries[0].sets[1].reps = 20
        XCTAssertEqual(data.plans[0].days[0], original)
        try data.validate()
    }

    func testMealCopyPreservesGoalsSourceAndDestinationIdentity() throws {
        var data = sample()
        let date = Dates.fromKey("2026-10-06")!
        let source = data.week[0].meals[0]
        let destinationID = data.week[1].meals[1].id
        let originalWeek = data.week
        let goals = data.baseGoals
        try data.copyMeal(from: source, date: date, base: false, destinationID: destinationID)
        let destination = data.diet(date, base: false).meals[1]
        XCTAssertEqual(destination.id, destinationID); XCTAssertEqual(destination.name, "Pranzo")
        XCTAssertNotEqual(destination.items[0].id, source.items[0].id)
        XCTAssertEqual(destination.items[0].quantity, 100)
        XCTAssertNotNil(destination.items[0].snapshot)
        data.foods[0].nutrients.kcal = 999
        XCTAssertEqual(data.totals(data.diet(date, base: false)).kcal, 367)
        XCTAssertEqual(data.week, originalWeek); XCTAssertEqual(data.baseGoals, goals)
        try data.validate()
    }

    func testDietCopyKeepsGoalsAndRegeneratesMealAndItemIDs() throws {
        var data = sample()
        let date = Dates.fromKey("2026-10-07")!
        let source = data.week[0]
        let goals = data.baseGoals
        try data.copyDietMeals(from: source, date: date, base: true)
        let copy = data.week[2]
        XCTAssertEqual(data.week[0], source)
        XCTAssertEqual(copy.goals, goals)
        XCTAssertTrue(Set(copy.meals.map(\.id)).isDisjoint(with: Set(source.meals.map(\.id))))
        XCTAssertNotEqual(copy.meals[0].items[0].id, source.meals[0].items[0].id)
        data.week[2].meals[0].items[0].quantity = 300
        XCTAssertEqual(data.week[0].meals[0].items[0].quantity, 100)
        try data.validate()
    }

    func testInvalidCopiesLeaveDataUnchanged() throws {
        var data = sample()
        let original = data, date = Dates.fromKey("2026-10-06")!
        XCTAssertThrowsError(try data.duplicatePlan(UUID(), name: "Copia"))
        XCTAssertThrowsError(try data.duplicateDay(planID: data.plans[0].id, dayID: UUID(), name: "Copia"))
        XCTAssertThrowsError(try data.copyMeal(from: data.week[0].meals[0], date: date, base: false, destinationID: UUID()))
        let invalid = Meal(name: "Pranzo", items: [MealItem(foodID: UUID(), quantity: 100)])
        XCTAssertThrowsError(try data.copyMeal(from: invalid, date: date, base: false, destinationID: data.week[1].meals[1].id))
        XCTAssertEqual(data, original)
    }

    func testBackupPreservesFullDataAndPhotosWithTimerStopped() throws {
        var data = sample()
        let date = Dates.fromKey("2026-10-05")!
        data.editDiet(date, base: false) { $0.meals[0].items[0].quantity = 200 }
        let entry = data.plans[0].days[0].entries[0]
        data.timer = RestTimer(entryID: entry.id, name: "Panca", duration: 90, deadline: Date().addingTimeInterval(90))
        let bytes = try BackupCodec.encode(data)
        let imported = try BackupCodec.decode(bytes)
        var expected = data; expected.timer = nil
        XCTAssertEqual(imported, expected)
        XCTAssertEqual(imported.exercises[0].photo, data.exercises[0].photo)
        XCTAssertEqual(imported.exercises[0].musclePhoto, data.exercises[0].musclePhoto)
        XCTAssertNotNil(data.timer)
    }

    func testInvalidBackupsAreRejected() throws {
        let data = sample()
        XCTAssertThrowsError(try BackupCodec.decode(Data()))
        XCTAssertThrowsError(try BackupCodec.decode(Data("{bad-json}".utf8)))
        for (format, version) in [("OtherApp", 1), ("DailyFit", 99)] {
            let envelope = BackupEnvelope(format: format, version: version, exportedAt: Date(), data: data)
            XCTAssertThrowsError(try BackupCodec.decode(JSONEncoder().encode(envelope)))
        }
        var broken = data; broken.plans[0].days[0].entries[0].exerciseID = UUID()
        let envelope = BackupEnvelope(format: "DailyFit", version: 1, exportedAt: Date(), data: broken)
        XCTAssertThrowsError(try BackupCodec.decode(JSONEncoder().encode(envelope)))
        XCTAssertThrowsError(try BackupCodec.decode(Data(repeating: 0, count: BackupCodec.sizeLimit + 1)))
    }

    @MainActor
    func testRestoreSuccessfulWriteAndStaleSaveCannotReplaceIt() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder)
        let store = AppStore(repository: repository)
        await store.load()
        XCTAssertTrue(store.ready)
        let old = store.data
        let imported = try BackupCodec.decode(BackupCodec.encode(sample()))
        let success = await store.restoreBackup(imported)
        XCTAssertTrue(success)
        let exported = try await store.exportSnapshot(store.data)
        XCTAssertEqual(exported, imported)
        try await repository.save(old, revision: 1)
        let reloaded = try await repository.load()
        XCTAssertEqual(reloaded, imported)
        await store.flush()
    }

    @MainActor
    func testRestoreDiskFailureKeepsCurrentData() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(folder: folder)
        let store = AppStore(repository: repository)
        await store.load()
        XCTAssertTrue(store.ready)
        let original = store.data
        let database = SQLiteRecords(url: folder.appendingPathComponent("records-v3.sqlite"))
        let originalRows = try database.read()
        try database.execute("CREATE TRIGGER fail_restore BEFORE INSERT ON records BEGIN SELECT RAISE(ABORT, 'Simulated disk failure'); END")
        let success = await store.restoreBackup(sample())
        XCTAssertFalse(success); XCTAssertEqual(store.data, original)
        XCTAssertEqual(try database.read(), originalRows)
        try database.execute("DROP TRIGGER fail_restore")
        await store.flush()
    }

    @MainActor
    func testNavigationKeepsTrainingDayAcrossSectionSwitches() async {
        let navigation = NavigationState(), plan = UUID(), day = UUID()
        navigation.gymPath = [.plan(plan), .day(plan, day)]
        let path = navigation.gymPath
        navigation.area = 1
        XCTAssertEqual(navigation.gymPath, path)
        navigation.area = 0
        XCTAssertEqual(navigation.gymPath, path); XCTAssertTrue(navigation.viewingTrainingDay)
        navigation.resetAfterRestore()
        XCTAssertTrue(navigation.gymPath.isEmpty); XCTAssertFalse(navigation.viewingTrainingDay)
    }

    func testScreenAwakeOnlyDuringVisibleActiveWorkout() {
        XCTAssertTrue(ScreenAwakePolicy.enabled(preference: true, active: true, gymVisible: true, viewingDay: true, editing: false))
        XCTAssertFalse(ScreenAwakePolicy.enabled(preference: false, active: true, gymVisible: true, viewingDay: true, editing: false))
        XCTAssertFalse(ScreenAwakePolicy.enabled(preference: true, active: false, gymVisible: true, viewingDay: true, editing: false))
        XCTAssertFalse(ScreenAwakePolicy.enabled(preference: true, active: true, gymVisible: false, viewingDay: true, editing: false))
        XCTAssertFalse(ScreenAwakePolicy.enabled(preference: true, active: true, gymVisible: true, viewingDay: false, editing: false))
        XCTAssertFalse(ScreenAwakePolicy.enabled(preference: true, active: true, gymVisible: true, viewingDay: true, editing: true))
    }

    func testSpreadsheetContainsEmptyDaysAndSnapshotNutrition() throws {
        var data = sample()
        let date = Dates.fromKey("2026-10-05")!
        data.editDiet(date, base: false) { $0.meals[0].items[0].quantity = 200 }
        data.foods[0].nutrients.kcal = 999
        let sheets = try SpreadsheetExport.sheets(for: data)
        XCTAssertEqual(sheets.count, 11)
        let days = try XCTUnwrap(sheets.first { $0.name == "Giornate palestra" })
        XCTAssertTrue(days.rows.contains { $0.contains(.text("Vuoto")) })
        let totals = try XCTUnwrap(sheets.first { $0.name == "Totali dieta" })
        XCTAssertTrue(totals.rows.contains { $0[0] == .text("Personalizzata") && $0[3] == .number(734) })
        let personal = try XCTUnwrap(totals.rows.first { $0[0] == .text("Personalizzata") })
        let exportedDate = try XCTUnwrap(SpreadsheetExport.calendarDate("2026-10-05"))
        XCTAssertEqual(personal[2], .date(exportedDate))
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(utc.component(.day, from: exportedDate), 5)
        XCTAssertEqual(utc.component(.hour, from: exportedDate), 0)
        let goals = try XCTUnwrap(sheets.first { $0.name == "Obiettivi base" })
        XCTAssertEqual(goals.rows[0][1], .number(500)); XCTAssertEqual(goals.rows[0][5], .number(140))
        XCTAssertTrue(sheets.allSatisfy { sheet in sheet.rows.allSatisfy { $0.count == sheet.headers.count } })
    }

    func testLongUnicodeNotesExportWithoutTruncationOrFormulas() throws {
        var data = sample()
        let text = String(repeating: "=SUM(1;2) & <serie> 🏋️\n", count: 1600)
        data.notes[0].body = text
        let sheets = try SpreadsheetExport.sheets(for: data)
        let diary = try XCTUnwrap(sheets.first { $0.name == "Diario" })
        let rejoined = diary.rows.map { row -> String in if case .text(let value) = row[4] { return value }; return "" }.joined()
        XCTAssertEqual(rejoined, text)
        XCTAssertGreaterThan(diary.rows.count, 1)
        XCTAssertTrue(SpreadsheetExport.chunks(text).allSatisfy { $0.utf16.count <= 1000 })
        let bytes = try SpreadsheetExport.encode(data)
        let entries = try unzipStored(bytes)
        for (name, content) in entries where name.hasSuffix(".xml") || name.hasSuffix(".rels") {
            XCTAssertTrue(XMLParser(data: content).parse(), "XML non valido: \(name)")
            XCTAssertFalse(String(decoding: content, as: UTF8.self).contains("<f>"))
        }
        let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "org.openxmlformats.spreadsheetml.sheet")
        attachment.name = "DailyFit-test-export.xlsx"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testExcelArchiveCRCColumnsAndInvalidCells() throws {
        XCTAssertEqual(ZIPStore.crc32(Data("123456789".utf8)), 0xCBF43926)
        XCTAssertEqual(ExcelWorkbook.column(0), "A"); XCTAssertEqual(ExcelWorkbook.column(25), "Z")
        XCTAssertEqual(ExcelWorkbook.column(26), "AA"); XCTAssertEqual(ExcelWorkbook.column(16383), "XFD")
        let bytes = try SpreadsheetExport.encode(sample())
        let entries = try unzipStored(bytes)
        XCTAssertEqual(entries.count, 16)
        XCTAssertNotNil(entries["[Content_Types].xml"])
        XCTAssertNotNil(entries["xl/_rels/workbook.xml.rels"])
        let bad = SpreadsheetSheet(name: "Invalid", headers: ["A"], rows: [[.number(.nan)]])
        XCTAssertThrowsError(try ExcelWorkbook.encode(sheets: [bad]))
        let wrongColumns = SpreadsheetSheet(name: "Invalid", headers: ["A"], rows: [[.text("A"), .text("B")]])
        XCTAssertThrowsError(try ExcelWorkbook.encode(sheets: [wrongColumns]))
    }

    // Independent parser of the ZIP local records, plus mandatory EOCD signature.
    private func unzipStored(_ bytes: Data) throws -> [String: Data] {
        func word(_ offset: Int, _ count: Int) throws -> Int {
            guard offset >= 0, offset + count <= bytes.count else { throw InputError.invalid("ZIP troncato.") }
            return (0..<count).reduce(0) { $0 | Int(bytes[offset + $1]) << ($1 * 8) }
        }
        var offset = 0, files: [String: Data] = [:]
        while try word(offset, 4) == 0x04034B50 {
            XCTAssertEqual(try word(offset + 8, 2), 0)
            let length = try word(offset + 18, 4), nameLength = try word(offset + 26, 2), extraLength = try word(offset + 28, 2)
            let start = offset + 30, contentStart = start + nameLength + extraLength
            guard contentStart + length <= bytes.count else { throw InputError.invalid("ZIP troncato.") }
            let name = String(decoding: bytes[start..<(start + nameLength)], as: UTF8.self)
            files[name] = bytes.subdata(in: contentStart..<(contentStart + length))
            offset = contentStart + length
        }
        XCTAssertEqual(try word(offset, 4), 0x02014B50)
        XCTAssertEqual(try word(bytes.count - 22, 4), 0x06054B50)
        XCTAssertEqual(try word(bytes.count - 12, 2), files.count)
        return files
    }
}

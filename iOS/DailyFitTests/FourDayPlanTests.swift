import XCTest
import Foundation
@testable import DailyFit

final class FourDayPlanTests: XCTestCase {
    func testInitialPlanMatchesAllFourDaysAndTwentyFourExercises() throws {
        let data = SeedCatalog.makeData()
        let plan = try XCTUnwrap(data.plans.first)
        XCTAssertEqual(data.plans.count, 1)
        XCTAssertEqual(plan.name, SeedCatalog.fourDayPlanName)
        XCTAssertEqual(plan.days.map(\.name), ["Lunedì — Parte alta A", "Martedì — Parte bassa A", "Giovedì — Parte alta B", "Venerdì — Parte bassa B"])
        let expected: [[(String, Int, String)]] = [
            [("Panca piana bilanciere", 3, "6"), ("Panca inclinata manubri", 3, "8"), ("Trazioni supine secondarie", 2, "8"), ("T-bar con appoggio al petto", 3, "8"), ("Alzate laterali", 2, "10"), ("Alzate a busto flesso", 2, "10")],
            [("Squat pesante", 3, "6"), ("Leg extension", 3, "8"), ("Stacco sumo leggero", 2, "8"), ("Leg curl", 3, "8"), ("Calf in piedi", 3, "15"), ("Crunch", 2, "12–20")],
            [("Trazioni supine pesanti", 3, "4"), ("Lat machine stretta supina", 2, "8"), ("Panca piana secondaria", 3, "8"), ("Panca inclinata manubri", 3, "8"), ("Alzate laterali", 2, "10"), ("Alzate a busto flesso", 2, "10")],
            [("Stacco sumo pesante", 3, "4"), ("Leg curl", 3, "8"), ("Squat secondario", 2, "8"), ("Leg extension", 3, "8"), ("Calf seduto", 3, "15"), ("Plank", 2, "20–40 s")]
        ]
        for (day, rows) in zip(plan.days, expected) {
            XCTAssertEqual(day.entries.count, 6)
            for (entry, row) in zip(day.entries, rows) {
                let exercise = try XCTUnwrap(data.exercise(entry.exerciseID))
                XCTAssertEqual(entry.displayName(for: exercise), row.0)
                XCTAssertEqual(entry.sets.count, row.1)
                XCTAssertTrue(entry.sets.allSatisfy { $0.displayTarget == row.2 && $0.load == 0 })
                XCTAssertEqual(entry.rest, 90)
            }
        }
        let entries = plan.days.flatMap(\.entries), sets = entries.flatMap(\.sets)
        XCTAssertEqual(entries.count, 24); XCTAssertEqual(sets.count, 62)
        XCTAssertEqual(Set(entries.map(\.id)).count, 24)
        XCTAssertEqual(Set(sets.map(\.id)).count, 62)
        XCTAssertEqual(entries[0].exerciseID, entries[14].exerciseID)
        try data.validate()
    }

    func testPlanImportPreservesPersonalCatalogAndDoesNotReplaceEditedPlan() throws {
        let catalog = SeedCatalog.makeData().exercises
        var data = AppData()
        var personal = catalog[0]
        personal.execution = "Descrizione personale"; personal.photo = nil
        data.exercises = [personal]
        data.plans = [TrainingPlan(name: "La mia scheda")]
        data.notes = [DiaryNote(title: "Appunto", body: "Personale")]
        let before = data
        XCTAssertTrue(try SeedCatalog.installDefaultsIfNeeded(to: &data, catalog: catalog))
        XCTAssertEqual(data.exercises[0], personal)
        XCTAssertEqual(data.plans.first, before.plans.first)
        XCTAssertEqual(data.notes, before.notes); XCTAssertEqual(data.foods, before.foods)
        XCTAssertEqual(data.plans[1].days[0].entries[0].exerciseID, personal.id)
        data.plans[1].days[0].entries[0].sets[0].load = 42.5
        let edited = data
        XCTAssertFalse(try SeedCatalog.installDefaultsIfNeeded(to: &data, catalog: catalog))
        XCTAssertEqual(data, edited)
    }

    func testIncompletePlanImportLeavesExistingDataUntouched() throws {
        var data = AppData()
        data.plans = [TrainingPlan(name: "Personale")]
        let before = data
        var catalog = SeedCatalog.makeData().exercises
        catalog.removeAll { $0.name == "Plank" }
        XCTAssertThrowsError(try SeedCatalog.installDefaultsIfNeeded(to: &data, catalog: catalog))
        XCTAssertEqual(data, before)
    }

    func testTargetsAcceptRangesAndSecondsAndRejectInvalidValues() throws {
        let reps = try TrainingSet.parseTarget("12–20", unit: .repetitions)
        XCTAssertEqual(reps.lower, 12); XCTAssertEqual(reps.upper, 20)
        let seconds = try TrainingSet.parseTarget("20 - 40", unit: .seconds)
        XCTAssertEqual(seconds.lower, 20); XCTAssertEqual(seconds.upper, 40)
        XCTAssertNil(try TrainingSet.parseTarget("8", unit: .repetitions).upper)
        for text in ["", "0", "20-12", "1.5", "-8", "2-3-4", "9999999999999999999999999", "1-9999999999999999999999"] {
            XCTAssertThrowsError(try TrainingSet.parseTarget(text, unit: .repetitions), text)
        }
        XCTAssertThrowsError(try TrainingSet.parseTarget("1000", unit: .repetitions))
        XCTAssertThrowsError(try TrainingSet.parseTarget("3601", unit: .seconds))
        XCTAssertEqual(try TrainingSet.parseTarget("3600", unit: .seconds).lower, 3600)
        XCTAssertThrowsError(try TrainingSet(reps: 5000, upperReps: 1).validate())
    }

    func testLegacySetsAndEntriesDecodeAndNewTargetsSurviveBackup() throws {
        var data = SeedCatalog.makeData()
        let original = data.plans[0].days[0].entries[0]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "nameOverride")
        var sets = try XCTUnwrap(json["sets"] as? [[String: Any]])
        for index in sets.indices { sets[index].removeValue(forKey: "upperReps"); sets[index].removeValue(forKey: "unit") }
        json["sets"] = sets
        let legacy = try JSONDecoder().decode(TrainingEntry.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.nameOverride)
        XCTAssertTrue(legacy.sets.allSatisfy { $0.effectiveUnit == .repetitions && $0.upperReps == nil && $0.reps == 6 })
        XCTAssertEqual(legacy.id, original.id)
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(data)), data)
        data.plans[0].days[0].entries[0].nameOverride = String(repeating: "a", count: 81)
        XCTAssertThrowsError(try data.validate())
    }

    func testCopiesAndExcelPreserveTimedRangesAndVariantNames() throws {
        let data = SeedCatalog.makeData(), original = data.plans[0]
        var copy = original.duplicated(name: "Copia")
        let source = original.days[3].entries[5], copied = copy.days[3].entries[5]
        XCTAssertNotEqual(source.id, copied.id)
        XCTAssertNotEqual(source.sets[0].id, copied.sets[0].id)
        XCTAssertEqual(source.sets[0].displayTarget, copied.sets[0].displayTarget)
        XCTAssertEqual(copy.days[3].entries[0].nameOverride, "Stacco sumo pesante")
        copy.days[3].entries[5].sets[0].upperReps = 60
        XCTAssertEqual(source.sets[0].upperReps, 40)
        let sheet = try XCTUnwrap(SpreadsheetExport.sheets(for: data).first { $0.name == "Serie" })
        XCTAssertEqual(sheet.rows.count, 62)
        XCTAssertTrue(sheet.rows.allSatisfy { $0.count == sheet.headers.count })
        let plank = sheet.rows.filter { $0[4] == .text("Plank") }
        XCTAssertEqual(plank.count, 2)
        XCTAssertEqual(plank[0][6], .number(20)); XCTAssertEqual(plank[0][13], .number(40)); XCTAssertEqual(plank[0][14], .text("Secondi"))
        XCTAssertTrue(sheet.rows.contains { $0[4] == .text("Crunch") && $0[13] == .number(20) && $0[14] == .text("Ripetizioni") })
        XCTAssertTrue(sheet.rows.contains { $0[4] == .text("Squat pesante") })
    }
}

import Foundation
import Combine

enum GymRoute: Hashable {
    case plan(UUID)
    case day(UUID, UUID)
}

@MainActor
final class NavigationState: ObservableObject {
    @Published var area = 0
    @Published var gymSection = 0
    @Published var gymPath: [GymRoute] = []

    var viewingTrainingDay: Bool {
        guard let last = gymPath.last else { return false }
        if case .day = last { return gymSection == 0 }
        return false
    }

    func resetAfterRestore() {
        gymPath = []
        gymSection = 0
        area = 0
    }
}

enum ScreenAwakePolicy {
    static func enabled(preference: Bool, active: Bool, gymVisible: Bool, viewingDay: Bool, editing: Bool) -> Bool {
        preference && active && gymVisible && viewingDay && !editing
    }
}

extension TrainingEntry {
    func duplicated() -> TrainingEntry {
        TrainingEntry(exerciseID: exerciseID, sets: sets.map { TrainingSet(reps: $0.reps, load: $0.load, upperReps: $0.upperReps, unit: $0.unit) }, rest: rest, nameOverride: nameOverride)
    }
}

extension TrainingDay {
    func duplicated(name: String? = nil) -> TrainingDay {
        TrainingDay(name: name ?? self.name, entries: entries.map { $0.duplicated() })
    }
}

extension TrainingPlan {
    func duplicated(name: String) -> TrainingPlan {
        TrainingPlan(name: name, days: days.map { $0.duplicated() })
    }
}

extension AppData {
    mutating func duplicatePlan(_ id: UUID, name: String) throws {
        let clean = try Input.text(name, label: "Scheda", limit: 80)
        guard let source = plans.first(where: { $0.id == id }) else { throw InputError.invalid("Scheda non disponibile.") }
        plans.append(source.duplicated(name: clean))
    }

    mutating func duplicateDay(planID: UUID, dayID: UUID, name: String) throws {
        let clean = try Input.text(name, label: "Giornata", limit: 80)
        guard let p = plans.firstIndex(where: { $0.id == planID }),
              let source = plans[p].days.first(where: { $0.id == dayID }) else { throw InputError.invalid("Giornata non disponibile.") }
        plans[p].days.append(source.duplicated(name: clean))
    }

    // Copies food/quantity only. The destination keeps its name, type and goals.
    mutating func copyMeal(from source: Meal, date: Date, base: Bool, destinationID: UUID) throws {
        guard diet(date, base: base).meals.contains(where: { $0.id == destinationID }) else {
            throw InputError.invalid("Pasto di destinazione non disponibile.")
        }
        let items = try copiedMealItems(source.items, base: base)
        editDiet(date, base: base) { day in
            if let m = day.meals.firstIndex(where: { $0.id == destinationID }) { day.meals[m].items = items }
        }
    }

    mutating func copyDietMeals(from source: DietDay, date: Date, base: Bool) throws {
        let meals = try source.meals.map { meal in
            try Meal(name: meal.name, isSnack: meal.isSnack, items: copiedMealItems(meal.items, base: base))
        }
        editDiet(date, base: base) { $0.meals = meals }
    }

    private func copiedMealItems(_ source: [MealItem], base: Bool) throws -> [MealItem] {
        try source.map { item -> MealItem in
            guard let food = food(item) else { throw InputError.invalid("Alimento non disponibile.") }
            return MealItem(foodID: item.foodID, quantity: item.quantity, snapshot: base ? item.snapshot : food)
        }
    }
}

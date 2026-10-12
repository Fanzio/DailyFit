import Foundation

extension AppData {
    /// Compatibility is for already stored values; new foods still require grams.
    var legacyFoodIDs: Set<UUID> {
        var ids = Set(foods.filter { $0.unit == .ml }.map(\.id))
        func collect(_ day: DietDay) {
            for item in day.meals.flatMap(\.items) {
                if let food = item.snapshot, food.unit == .ml { ids.insert(food.id) }
            }
        }
        for day in week { collect(day) }
        for day in dates.values { collect(day) }
        return ids
    }

    var hasLegacyFoodUnits: Bool {
        func legacy(_ day: DietDay) -> Bool {
            day.meals.contains { $0.items.contains { $0.snapshot?.unit == .ml } }
        }
        return foods.contains { $0.unit == .ml } || week.contains(where: legacy) || dates.values.contains(where: legacy)
    }

    /// Changing a catalog unit must not relabel existing meal quantities automatically.
    mutating func saveGramFood(_ food: Food) throws {
        try food.validate()
        if let old = foods.first(where: { $0.id == food.id }), old.unit == .ml {
            func preserve(_ day: inout DietDay) {
                for m in day.meals.indices {
                    for i in day.meals[m].items.indices {
                        if day.meals[m].items[i].foodID == old.id && day.meals[m].items[i].snapshot == nil {
                            day.meals[m].items[i].snapshot = old
                        }
                    }
                }
            }
            for i in week.indices { preserve(&week[i]) }
            for key in Array(dates.keys) {
                if var day = dates[key] { preserve(&day); dates[key] = day }
            }
        }
        if let index = foods.firstIndex(where: { $0.id == food.id }) { foods[index] = food }
        else { foods.append(food) }
    }

    /// The user supplies the gram quantity and the reviewed per-100-g food explicitly.
    mutating func correctLegacyPortion(date: Date, base: Bool, mealID: UUID, itemID: UUID,
                                      food: Food, grams: Double) throws {
        try food.validate()
        guard grams.isFinite, grams > 0, grams <= 100000,
              let meal = diet(date, base: base).meals.first(where: { $0.id == mealID }),
              let item = meal.items.first(where: { $0.id == itemID }),
              item.foodID == food.id, self.food(item)?.unit == .ml else {
            throw InputError.invalid("La porzione da correggere non è più disponibile.")
        }
        editDiet(date, base: base) { day in
            guard let m = day.meals.firstIndex(where: { $0.id == mealID }),
                  let i = day.meals[m].items.firstIndex(where: { $0.id == itemID }) else { return }
            day.meals[m].items[i].quantity = grams
            day.meals[m].items[i].snapshot = food
        }
    }
}

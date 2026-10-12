import Foundation

enum ShoppingGroup: String, CaseIterable, Identifiable, Hashable {
    case breakfast = "Colazione", lunch = "Pranzo", dinner = "Cena", snacks = "Spuntini", other = "Altri pasti"
    var id: String { rawValue }
    static func group(for meal: Meal) -> Self {
        if meal.isSnack { return .snacks }
        switch meal.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "colazione": return .breakfast
        case "pranzo": return .lunch
        case "cena": return .dinner
        default: return .other
        }
    }
}

struct ShoppingKey: Hashable {
    let foodID: UUID
    let unit: String
}

struct ShoppingItem: Identifiable, Equatable {
    var id: ShoppingKey
    var name: String
    var quantity: Double
    var unit: FoodUnit
}

struct ShoppingSection: Identifiable {
    var id: ShoppingGroup
    var items: [ShoppingItem]
}

enum ShoppingList {
    // Exactly one base week. Personalized dates never change this recurring list.
    static func sections(for data: AppData) -> [ShoppingSection] {
        var groups: [ShoppingGroup: [ShoppingKey: ShoppingItem]] = [:]
        for day in data.week {
            for meal in day.meals {
                let group = ShoppingGroup.group(for: meal)
                for portion in meal.items {
                    guard let food = data.food(portion) else { continue }
                    let key = ShoppingKey(foodID: food.id, unit: food.unit.rawValue)
                    var item = groups[group]?[key] ?? ShoppingItem(id: key, name: food.name, quantity: 0, unit: food.unit)
                    item.quantity += portion.quantity
                    groups[group, default: [:]][key] = item
                }
            }
        }
        return ShoppingGroup.allCases.compactMap { group in
            guard let items = groups[group], !items.isEmpty else { return nil }
            return ShoppingSection(id: group, items: sorted(Array(items.values)))
        }
    }

    static func totals(for data: AppData) -> [ShoppingItem] {
        var totals: [ShoppingKey: ShoppingItem] = [:]
        for section in sections(for: data) {
            for item in section.items {
                var total = totals[item.id] ?? ShoppingItem(id: item.id, name: item.name, quantity: 0, unit: item.unit)
                total.quantity += item.quantity
                totals[item.id] = total
            }
        }
        return sorted(Array(totals.values))
    }

    private static func sorted(_ items: [ShoppingItem]) -> [ShoppingItem] {
        items.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            if $0.id.unit != $1.id.unit { return $0.id.unit < $1.id.unit }
            return $0.id.foodID.uuidString < $1.id.foodID.uuidString
        }
    }
}

extension AppData {
    mutating func moveMealItem(date: Date, base: Bool, mealID: UUID, itemID: UUID, offset: Int) throws {
        guard offset == -1 || offset == 1,
              let meal = diet(date, base: base).meals.first(where: { $0.id == mealID }),
              let source = meal.items.firstIndex(where: { $0.id == itemID }),
              meal.items.indices.contains(source + offset) else { throw InputError.invalid("Impossibile spostare l’alimento in questa posizione.") }
        editDiet(date, base: base) { day in
            if let m = day.meals.firstIndex(where: { $0.id == mealID }) {
                day.meals[m].items.swapAt(source, source + offset)
            }
        }
    }
}

import Foundation

enum InputError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

enum Input {
    static func text(_ value: String, label: String, limit: Int, required: Bool = true) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!required || !value.isEmpty), value.count <= limit else {
            throw InputError.invalid("\(label): inserisci un testo entro \(limit) caratteri.")
        }
        return value
    }
    static func decimal(_ value: String, label: String, range: ClosedRange<Double>, optional: Bool = false) throws -> Double? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if optional && value.isEmpty { return nil }
        guard value.count <= 12,
              value.range(of: #"^\d+(?:[.,]\d+)?$"#, options: .regularExpression) != nil,
              let number = Double(value.replacingOccurrences(of: ",", with: ".")),
              number.isFinite, range.contains(number) else {
            if range.lowerBound == 0 && range.upperBound == Double.greatestFiniteMagnitude {
                throw InputError.invalid("\(label): inserisci un numero pari o superiore a zero.")
            }
            throw InputError.invalid("\(label): inserisci un numero tra \(range.lowerBound.formatted()) e \(range.upperBound.formatted()).")
        }
        return number
    }
    static func webURL(_ text: String) throws -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        guard text.count <= 2048, let url = URL(string: text),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            throw InputError.invalid("Inserisci un indirizzo completo con https:// o http://.")
        }
        return url
    }
    static func chatURL(_ text: String) throws -> URL {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = try webURL(clean) ?? URL(string: "https://chatgpt.com/")!
        guard url.scheme == "https", url.host == "chatgpt.com", url.port == nil,
              url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" || url.path.range(of: #"^/c/[A-Za-z0-9-]+/?$"#, options: .regularExpression) != nil else {
            throw InputError.invalid("Usa https://chatgpt.com/c/ seguito dall’ID della chat privata, oppure lascia vuoto.")
        }
        return url
    }
}

struct Exercise: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var muscle: String
    var execution: String
    var video: String = ""
    var photo: Data? = nil
    var musclePhoto: Data? = nil
    // Private runtime references. Public backups must embed bytes and remove these fields.
    var photoFile: String? = nil
    var musclePhotoFile: String? = nil
    var hasMusclePhoto: Bool { musclePhoto != nil || musclePhotoFile != nil }
    var archived = false
    static let groups = ["Petto", "Dorso", "Spalle", "Bicipiti", "Tricipiti", "Quadricipiti", "Femorali", "Glutei", "Polpacci", "Addominali", "Full body", "Altro"]
    func validate() throws {
        _ = try Input.text(name, label: "Nome", limit: 80)
        _ = try Input.text(execution, label: "Esecuzione", limit: 3000, required: false)
        guard Self.groups.contains(muscle) else { throw InputError.invalid("Gruppo muscolare non valido.") }
        _ = try Input.webURL(video)
        if let photo, photo.isEmpty || photo.count > 2_000_000 { throw InputError.invalid("Immagine vuota o troppo grande.") }
        if let musclePhoto, musclePhoto.isEmpty || musclePhoto.count > 2_000_000 { throw InputError.invalid("Immagine dei muscoli vuota o troppo grande.") }
        for filename in [photoFile, musclePhotoFile].compactMap({ $0 }) {
            guard filename.range(of: #"^[0-9a-f]{64}\.bin$"#, options: .regularExpression) != nil else {
                throw InputError.invalid("Riferimento immagine non valido.")
            }
        }
    }
}
enum TrainingSetUnit: String, Codable, CaseIterable { case repetitions, seconds }

struct TrainingSet: Identifiable, Codable, Equatable {
    var id = UUID()
    var reps: Int = 10
    var load: Double = 0
    var upperReps: Int? = nil
    var unit: TrainingSetUnit? = nil
    var effectiveUnit: TrainingSetUnit { unit ?? .repetitions }
    var targetText: String { String(reps) + (upperReps.map { "–\($0)" } ?? "") }
    var displayTarget: String { targetText + (effectiveUnit == .seconds ? " s" : "") }
    static func parseTarget(_ text: String, unit: TrainingSetUnit) throws -> (lower: Int, upper: Int?) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        guard clean.count <= 25, clean.range(of: #"^\d+(?:\s*-\s*\d+)?$"#, options: .regularExpression) != nil else {
            throw InputError.invalid("Inserisci un intero oppure un intervallo, per esempio 8 o 12–20.")
        }
        let parts = clean.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard let lower = Int(parts[0]) else { throw InputError.invalid("Valore della serie non valido.") }
        let upper = parts.count == 2 ? Int(parts[1]) : nil
        if parts.count == 2 && upper == nil { throw InputError.invalid("Intervallo non valido.") }
        try TrainingSet(reps: lower, upperReps: upper, unit: unit).validate()
        return (lower, upper)
    }
    func validate() throws {
        let maximum = effectiveUnit == .seconds ? 3600 : 999
        guard (1...maximum).contains(reps), load.isFinite, (0...2000).contains(load),
              upperReps.map({ $0 >= reps && $0 <= maximum }) ?? true else {
            throw InputError.invalid("Serie: valori interi da 1 a \(maximum), massimo non inferiore al minimo e carico da 0 a 2000 kg.")
        }
    }
}
struct TrainingEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var exerciseID: UUID
    var sets = [TrainingSet(), TrainingSet(), TrainingSet()]
    var rest: Int = 90
    var nameOverride: String? = nil
    func displayName(for exercise: Exercise) -> String { nameOverride ?? exercise.name }
}
struct TrainingDay: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var entries: [TrainingEntry] = []
}
struct TrainingPlan: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var days: [TrainingDay] = []
}
struct DiaryNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var body = ""
    var updatedAt = Date()
    var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        return body.split(separator: "\n").first.map { String($0.prefix(80)) } ?? "Nuova nota"
    }
}
struct Nutrients: Codable, Equatable {
    var kcal: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carbs: Double = 0
    func scaled(_ factor: Double) -> Self {
        Self(kcal: kcal * factor, protein: protein * factor, fat: fat * factor, carbs: carbs * factor)
    }
    static func + (a: Self, b: Self) -> Self {
        Self(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, fat: a.fat + b.fat, carbs: a.carbs + b.carbs)
    }
    func validate() throws {
        guard [kcal, protein, fat, carbs].allSatisfy({ $0.isFinite && (0...10000).contains($0) }) else {
            throw InputError.invalid("Valori nutrizionali non validi.")
        }
    }
}
// Legacy ml remains decodable for manual correction; newly entered foods use g.
enum FoodUnit: String, Codable { case g, ml }
struct Food: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var unit: FoodUnit = .g
    var nutrients: Nutrients
    var source = "Inserito dall’utente"
    var sourceURL = ""
    var archived = false
    func validate(allowLegacyUnit: Bool = false) throws {
        guard unit == .g || allowLegacyUnit else { throw InputError.invalid("Usa solo grammi: i valori nutrizionali devono riferirsi a 100 g. Un archivio in ml richiede una conversione esplicita.") }
        _ = try Input.text(name, label: "Alimento", limit: 100)
        try nutrients.validate()
        _ = try Input.text(source, label: "Fonte", limit: 300, required: false)
        _ = try Input.webURL(sourceURL)
    }
}
struct Goals: Codable, Equatable {
    var kcal: Double? = nil
    var proteinPerKg: Double? = nil
    var fatPerKg: Double? = nil
    var carbsPerKg: Double? = nil
    private var needsCarbsMigration = false

    init(kcal: Double? = nil, proteinPerKg: Double? = nil, fatPerKg: Double? = nil, carbsPerKg: Double? = nil) {
        self.kcal = kcal
        self.proteinPerKg = proteinPerKg
        self.fatPerKg = fatPerKg
        self.carbsPerKg = carbsPerKg
    }

    private enum CodingKeys: String, CodingKey { case kcal, proteinPerKg, fatPerKg, carbsPerKg }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kcal = try values.decodeIfPresent(Double.self, forKey: .kcal)
        proteinPerKg = try values.decodeIfPresent(Double.self, forKey: .proteinPerKg)
        fatPerKg = try values.decodeIfPresent(Double.self, forKey: .fatPerKg)
        carbsPerKg = try values.decodeIfPresent(Double.self, forKey: .carbsPerKg)
        needsCarbsMigration = !values.contains(.carbsPerKg)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(kcal, forKey: .kcal)
        try values.encodeIfPresent(proteinPerKg, forKey: .proteinPerKg)
        try values.encodeIfPresent(fatPerKg, forKey: .fatPerKg)
        // Explicit null distinguishes a deliberately empty target from the old format.
        try values.encode(carbsPerKg, forKey: .carbsPerKg)
    }

    mutating func migrateLegacyCarbs(weight: Double?) {
        guard needsCarbsMigration else { return }
        needsCarbsMigration = false
        // Preserve the previous calculated target once, then treat it as user-editable.
        if let weight, weight.isFinite, weight > 0,
           let kcal, let proteinPerKg, let fatPerKg {
            let ratio = (kcal / weight - 4 * proteinPerKg - 9 * fatPerKg) / 4
            if ratio.isFinite { carbsPerKg = max(0, ratio) }
        }
    }

    func targets(weight: Double?) throws -> Targets {
        guard [kcal, proteinPerKg, fatPerKg, carbsPerKg].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw InputError.invalid("Obiettivi non validi.")
        }
        if let weight, !weight.isFinite || weight <= 0 || weight > 500 { throw InputError.invalid("Peso non valido.") }
        if weight == nil && (proteinPerKg != nil || fatPerKg != nil || carbsPerKg != nil) { throw InputError.invalid("Inserisci il peso per usare i rapporti g/kg.") }
        let protein = proteinPerKg.flatMap { ratio in weight.map { $0 * ratio } }
        let fat = fatPerKg.flatMap { ratio in weight.map { $0 * ratio } }
        let carbs = carbsPerKg.flatMap { ratio in weight.map { $0 * ratio } }
        guard [protein, fat, carbs].compactMap({ $0 }).allSatisfy(\.isFinite) else {
            throw InputError.invalid("Obiettivi troppo grandi per essere calcolati.")
        }
        return Targets(kcal: kcal, protein: protein, fat: fat, carbs: carbs)
    }
}
struct Targets: Equatable {
    var kcal: Double? = nil
    var protein: Double? = nil
    var fat: Double? = nil
    var carbs: Double? = nil
}
struct MealItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var foodID: UUID
    var quantity: Double
    var snapshot: Food? = nil
}
struct Meal: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var isSnack = false
    var items: [MealItem] = []
}
struct DietDay: Codable, Equatable {
    var goals = Goals()
    var weight: Double? = nil
    var meals = [Meal(name: "Colazione"), Meal(name: "Pranzo"), Meal(name: "Cena")]
}
enum Dates {
    static let names = ["Lunedì", "Martedì", "Mercoledì", "Giovedì", "Venerdì", "Sabato", "Domenica"]
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }
    static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func weekday(_ date: Date) -> Int { (calendar.component(.weekday, from: date) + 5) % 7 }
    static func fromKey(_ key: String) -> Date? {
        guard key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)), Self.key(date) == key else { return nil }
        return date
    }
    static func shifting(_ date: Date, days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: date)! }
    static func inWeek(_ date: Date, weekday: Int) -> Date { shifting(date, days: weekday - Self.weekday(date)) }
}
struct RestTimer: Codable, Equatable {
    var id = UUID()
    var entryID: UUID
    var name: String
    var duration: Int
    var deadline: Date? = nil
    var pausedSeconds: Int = 0
    func remaining(at date: Date = Date()) -> Int {
        guard let deadline else { return max(0, min(3600, pausedSeconds)) }
        let seconds = deadline.timeIntervalSince(date)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min(3600, ceil(seconds)))
    }
    var running: Bool { deadline != nil }
    mutating func pause(at now: Date = Date()) { pausedSeconds = remaining(at: now); deadline = nil }
    mutating func resume(at now: Date = Date()) { deadline = now.addingTimeInterval(TimeInterval(pausedSeconds > 0 ? pausedSeconds : duration)); pausedSeconds = 0 }
}
struct AppData: Codable, Equatable {
    var schemaVersion = 1
    var exercises: [Exercise] = []
    var plans: [TrainingPlan] = []
    var notes: [DiaryNote] = []
    var foods: [Food] = []
    var bodyWeight: Double? = nil
    var week = (0..<7).map { _ in DietDay() }
    var dates: [String: DietDay] = [:]
    var chatLink = "https://chatgpt.com/"
    var timer: RestTimer? = nil
    var keepScreenAwake: Bool? = nil
    var defaultContentVersion: Int? = nil

    // The first base day holds the common targets; legacy daily fields stay readable.
    var baseGoals: Goals { week.first?.goals ?? Goals() }

    mutating func setBaseGoals(_ goals: Goals, weight: Double?) {
        bodyWeight = weight
        for i in week.indices { week[i].goals = goals }
    }

    mutating func migrateLegacyGoals() {
        for i in week.indices { week[i].goals.migrateLegacyCarbs(weight: bodyWeight) }
        for key in Array(dates.keys) {
            if var day = dates[key] {
                day.goals.migrateLegacyCarbs(weight: day.weight)
                dates[key] = day
            }
        }
    }

    func exercise(_ id: UUID) -> Exercise? { exercises.first { $0.id == id } }
    func food(_ item: MealItem) -> Food? { item.snapshot ?? foods.first { $0.id == item.foodID } }
    func diet(_ date: Date, base: Bool) -> DietDay { base ? week[Dates.weekday(date)] : dates[Dates.key(date)] ?? week[Dates.weekday(date)] }
    func targets(_ date: Date, base: Bool) throws -> Targets {
        try baseGoals.targets(weight: bodyWeight)
    }
    func totals(_ day: DietDay) -> Nutrients {
        day.meals.flatMap(\.items).reduce(Nutrients()) { total, item in total + (food(item)?.nutrients.scaled(item.quantity / 100) ?? Nutrients()) }
    }
    mutating func editDiet(_ date: Date, base: Bool, edit: (inout DietDay) -> Void) {
        let weekday = Dates.weekday(date)
        if base { edit(&week[weekday]); return }
        let key = Dates.key(date)
        if dates[key] == nil {
            var copy = week[weekday]
            copy.weight = bodyWeight
            // Value types preserve meal/item IDs inside this independent date only.
            for m in copy.meals.indices { for i in copy.meals[m].items.indices { copy.meals[m].items[i].snapshot = food(copy.meals[m].items[i]) } }
            dates[key] = copy
        }
        var copy = dates[key]!
        edit(&copy)
        dates[key] = copy
    }
    /// `previous` must be a validated value snapshot, never an imported document.
    /// Counts and identities stay global; field rules run only for changed records/dependencies.
    func validate(changesFrom previous: AppData? = nil, allowLegacyFoodUnits: Bool = false) throws {
        guard schemaVersion == 1, week.count == 7, exercises.count <= 5000, foods.count <= 10000,
              plans.count <= 1000, notes.count <= 10000, dates.count <= 50000 else { throw InputError.invalid("Archivio non compatibile o troppo grande.") }
        func unique(_ ids: [UUID]) throws {
            guard Set(ids).count == ids.count else { throw InputError.invalid("Identificativi duplicati nell’archivio.") }
        }
        func index<T: Identifiable>(_ values: [T]?) -> [T.ID: T] {
            Dictionary(uniqueKeysWithValues: (values ?? []).map { ($0.id, $0) })
        }
        try unique(exercises.map(\.id)); try unique(foods.map(\.id))
        try unique(plans.map(\.id)); try unique(notes.map(\.id))
        let oldExercises = index(previous?.exercises), oldFoods = index(previous?.foods)
        let allowedLegacyFoods = allowLegacyFoodUnits ? legacyFoodIDs : previous?.legacyFoodIDs ?? []
        let oldPlans = index(previous?.plans), oldNotes = index(previous?.notes)
        let exerciseIDs = Set(exercises.map(\.id))
        let foodsByID = index(foods)
        let exerciseReferencesChanged = exerciseIDs != Set(oldExercises.keys)
        let foodReferencesChanged = Set(foodsByID.keys) != Set(oldFoods.keys)
        for exercise in exercises where oldExercises[exercise.id] != exercise { try exercise.validate() }
        for food in foods where oldFoods[food.id] != food { try food.validate(allowLegacyUnit: allowedLegacyFoods.contains(food.id)) }
        for plan in plans {
            let oldPlan = oldPlans[plan.id]
            if !exerciseReferencesChanged && oldPlan == plan { continue }
            _ = try Input.text(plan.name, label: "Scheda", limit: 80)
            try unique(plan.days.map(\.id))
            let oldDays = index(oldPlan?.days)
            for day in plan.days {
                let oldDay = oldDays[day.id]
                if !exerciseReferencesChanged && oldDay == day { continue }
                _ = try Input.text(day.name, label: "Giornata", limit: 80)
                try unique(day.entries.map(\.id))
                let oldEntries = index(oldDay?.entries)
                for entry in day.entries {
                    if !exerciseReferencesChanged && oldEntries[entry.id] == entry { continue }
                    if let name = entry.nameOverride { _ = try Input.text(name, label: "Nome nella giornata", limit: 80) }
                    guard exerciseIDs.contains(entry.exerciseID), (1...3600).contains(entry.rest), (1...30).contains(entry.sets.count) else { throw InputError.invalid("Esercizio della scheda non valido.") }
                    try unique(entry.sets.map(\.id))
                    for set in entry.sets { try set.validate() }
                }
            }
        }
        for note in notes where oldNotes[note.id] != note {
            guard note.title.count <= 120, note.body.count <= 200000 else { throw InputError.invalid("Nota troppo lunga.") }
        }
        for (i, day) in week.enumerated() {
            if let previous, !foodReferencesChanged, previous.bodyWeight == bodyWeight,
               previous.week[i] == day { continue }
            try validateDiet(day, weight: bodyWeight, label: Dates.names[i], foodsByID: foodsByID, allowedLegacyFoods: allowedLegacyFoods)
        }
        for (key, day) in dates {
            if !foodReferencesChanged && previous?.dates[key] == day { continue }
            guard Dates.fromKey(key) != nil else { throw InputError.invalid("Data non valida nell’archivio.") }
            try validateDiet(day, weight: day.weight, label: key, foodsByID: foodsByID, allowedLegacyFoods: allowedLegacyFoods)
        }
        if previous?.chatLink != chatLink { _ = try Input.chatURL(chatLink) }
        if let timer, previous?.timer != timer || previous?.plans != plans {
            guard (1...3600).contains(timer.duration), (0...3600).contains(timer.pausedSeconds),
                  timer.deadline?.timeIntervalSinceReferenceDate.isFinite ?? true,
                  plans.flatMap(\.days).flatMap(\.entries).contains(where: { $0.id == timer.entryID }) else { throw InputError.invalid("Timer non valido.") }
        }
    }
    private func validateDiet(_ day: DietDay, weight: Double?, label: String, foodsByID: [UUID: Food], allowedLegacyFoods: Set<UUID>) throws {
        do { _ = try day.goals.targets(weight: weight) } catch { throw InputError.invalid("\(label): \(error.localizedDescription)") }
        guard day.meals.count >= 3, day.meals.count <= 100, Set(day.meals.map(\.id)).count == day.meals.count else { throw InputError.invalid("Pasti non validi.") }
        for meal in day.meals {
            _ = try Input.text(meal.name, label: "Pasto", limit: 80)
            guard Set(meal.items.map(\.id)).count == meal.items.count else { throw InputError.invalid("Alimenti duplicati nel pasto.") }
            for item in meal.items {
                guard let food = item.snapshot ?? foodsByID[item.foodID], item.quantity.isFinite, item.quantity > 0, item.quantity <= 100000 else { throw InputError.invalid("Quantità o alimento non valido.") }
                guard item.snapshot == nil || item.snapshot?.id == item.foodID else { throw InputError.invalid("Copia dell’alimento non coerente con il pasto.") }
                if item.snapshot != nil { try food.validate(allowLegacyUnit: allowedLegacyFoods.contains(food.id)) }
            }
        }
    }
}

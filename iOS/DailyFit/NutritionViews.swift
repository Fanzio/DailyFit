import SwiftUI

struct NutritionView: View {
    @State private var tab = 0
    @State private var settings = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Sezioni nutrizione", selection: $tab) { Text("Dieta").tag(0); Text("Alimenti").tag(1) }.pickerStyle(.segmented).padding()
                ZStack {
                    DietView().opacity(tab == 0 ? 1 : 0).allowsHitTesting(tab == 0).accessibilityHidden(tab != 0)
                    FoodCatalogView().opacity(tab == 1 ? 1 : 0).allowsHitTesting(tab == 1).accessibilityHidden(tab != 1)
                }
            }.background(FitTheme.background).navigationTitle("Nutrizione").navigationBarTitleDisplayMode(.large)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Impostazioni e backup") } }
                .sheet(isPresented: $settings) { SettingsView() }
        }
    }
}
struct NutrientRing: View {
    let name: String
    let value: Double
    let target: Double?
    let color: Color
    var fraction: Double { guard let target else { return 0 }; return target > 0 ? min(1, value / target) : value > 0 ? 1 : 0 }
    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 5)
                Circle().trim(from: 0, to: fraction).stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(formatNumber(value)).font(.caption.bold()).minimumScaleFactor(0.65).lineLimit(1).padding(5)
            }.aspectRatio(1, contentMode: .fit)
            Text(name).font(.caption2).lineLimit(1).minimumScaleFactor(0.6)
            Text(target.map { "/ " + formatNumber($0) } ?? "Obiettivo —").font(.caption2).foregroundStyle(FitTheme.muted).lineLimit(1).minimumScaleFactor(0.6)
            if let target, value > target { Text("+" + formatNumber(value - target)).font(.caption2).foregroundStyle(.orange) }
        }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore).accessibilityLabel("\(name): \(formatNumber(value)); obiettivo \(target.map(formatNumber) ?? "da impostare")")
    }
}
struct PortionRoute: Identifiable {
    var id = UUID()
    var mealID: UUID
    var food: Food
    var item: MealItem? = nil
}
struct MealRemoval: Identifiable {
    var id = UUID()
    var mealID: UUID
    var itemID: UUID? = nil
}
struct DietCopyRoute: Identifiable {
    var id = UUID()
    var source: DietDay
    var meal: Meal? = nil
    var date: Date
    var base: Bool
}
struct DietView: View {
    @EnvironmentObject private var store: AppStore
    @State private var date = Date()
    @State private var base = false
    @State private var goals = false
    @State private var pickerMeal: Meal? = nil
    @State private var portion: PortionRoute? = nil
    @State private var snack = false
    @State private var reset = false
    @State private var removal: MealRemoval? = nil
    @State private var copy: DietCopyRoute? = nil
    @State private var shopping = false
    @State private var orderingMeal: UUID? = nil
    @State private var expandedMeals: Set<UUID> = []
    private var day: DietDay { store.data.diet(date, base: base) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Tipo di dieta", selection: $base) { Text("Giorno").tag(false); Text("Dieta base").tag(true) }.pickerStyle(.segmented)
                if !base {
                    HStack {
                        Button { date = Dates.shifting(date, days: -7) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Settimana precedente")
                        DatePicker("Data", selection: $date, displayedComponents: .date).labelsHidden().frame(maxWidth: .infinity)
                        Button { date = Dates.shifting(date, days: 7) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Settimana successiva")
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(0..<7) { i in Button(String(Dates.names[i].prefix(3))) { date = Dates.inWeek(date, weekday: i) }.font(.caption.bold()).padding(12).background(Dates.weekday(date) == i ? FitTheme.lime : FitTheme.card, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(Dates.weekday(date) == i ? FitTheme.background : FitTheme.muted).accessibilityLabel(Dates.names[i]).accessibilityAddTraits(Dates.weekday(date) == i ? .isSelected : []) } }
                }
                HStack { Text(Dates.names[Dates.weekday(date)]).font(.title3.bold()); Spacer(); Button("Obiettivi base ↗") { goals = true }.font(.caption) }
                rings
                Button { shopping = true } label: { Label("Lista della spesa · dieta base", systemImage: "cart") }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                Text(base ? "Modifichi la dieta che si ripete ogni settimana." : store.data.dates[Dates.key(date)] != nil ? "Giornata personalizzata. La dieta base resta invariata." : "Questa giornata segue la dieta base. Le modifiche valgono solo per questa data.").font(.caption).foregroundStyle(FitTheme.muted)
                ForEach(day.meals) { meal in mealCard(meal) }
                Button("＋ Aggiungi spuntino") { snack = true }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                Button("Copia pasti in un altro giorno") { copy = DietCopyRoute(source: day, date: date, base: base) }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                if !base && store.data.dates[Dates.key(date)] != nil { Button("Ripristina dieta base per questa data") { reset = true }.font(.caption).frame(maxWidth: .infinity) }
            }.padding()
        }
        .sheet(isPresented: $goals) { GoalsEditor() }
        .sheet(isPresented: $shopping) { ShoppingListView() }
        .onChange(of: date) { _, _ in orderingMeal = nil; expandedMeals.removeAll() }
        .onChange(of: base) { _, _ in orderingMeal = nil; expandedMeals.removeAll() }
        .sheet(item: $copy) { DietCopyEditor(route: $0) }
        .sheet(item: $pickerMeal) { meal in FoodPicker { food in pickerMeal = nil; DispatchQueue.main.async { portion = PortionRoute(mealID: meal.id, food: food) } } }
        .sheet(item: $portion) { route in PortionEditor(route: route, date: date, base: base) }
        .sheet(isPresented: $snack) { NameEditor(title: "Nuovo spuntino", initial: "Spuntino") { name in store.change { data in data.editDiet(date, base: base) { day in day.meals.insert(Meal(name: name, isSnack: true), at: max(0, day.meals.count - 1)) } } } }
        .alert("Ripristinare la dieta base?", isPresented: $reset) { Button("Annulla", role: .cancel) {}; Button("Ripristina", role: .destructive) { store.delete(label: "Modifiche della data rimosse") { $0.dates.removeValue(forKey: Dates.key(date)) } } } message: { Text("Verranno rimosse solo le modifiche di questa data.") }
        .alert("Confermi la rimozione?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
            Button("Annulla", role: .cancel) { removal = nil }
            Button("Rimuovi", role: .destructive) { removeSelected() }
        } message: { Text(base ? "Modifichi la dieta base." : "Modifichi solo questa data.") }
    }
    private var rings: some View {
        let totals = store.data.totals(day)
        let targets = (try? store.data.targets(date, base: base)) ?? Targets()
        return HStack(alignment: .top, spacing: 10) { NutrientRing(name: "Kcal", value: totals.kcal, target: targets.kcal, color: FitTheme.lime); NutrientRing(name: "Proteine · g", value: totals.protein, target: targets.protein, color: .blue); NutrientRing(name: "Grassi · g", value: totals.fat, target: targets.fat, color: .orange); NutrientRing(name: "Carboidrati · g", value: totals.carbs, target: targets.carbs, color: .purple) }
    }
    private func mealCard(_ meal: Meal) -> some View {
        let isExpanded = expandedMeals.contains(meal.id)
        return FitCard {
            VStack(alignment: .leading, spacing: 12) {
                Button { toggleMeal(meal.id) } label: {
                    HStack {
                        Text(meal.name).font(.headline).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.caption.bold()).foregroundStyle(FitTheme.lime)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(meal.name)
                .accessibilityValue(isExpanded ? "Aperto" : "Chiuso")
                .accessibilityHint(meal.isSnack ? "Tocca per mostrare o nascondere i cibi. Tieni premuto per eliminare lo spuntino." : "Tocca per mostrare o nascondere i cibi.")
                .contextMenu {
                    if meal.isSnack {
                        Button("Elimina spuntino", systemImage: "trash", role: .destructive) { removal = MealRemoval(mealID: meal.id) }
                    }
                }
                if isExpanded { mealContents(meal) }
            }
        }
    }

    private func toggleMeal(_ id: UUID) {
        if expandedMeals.contains(id) {
            expandedMeals.remove(id)
            if orderingMeal == id { orderingMeal = nil }
        } else { expandedMeals.insert(id) }
    }

    private func mealContents(_ meal: Meal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { copy = DietCopyRoute(source: day, meal: meal, date: date, base: base) } label: { Label("Copia pasto", systemImage: "doc.on.doc") }
                    .accessibilityLabel("Copia \(meal.name) in un altro pasto")
                Spacer()
                Button("＋ Cibo") { pickerMeal = meal }
            }.font(.caption)
            if meal.items.count > 1 {
                Button(orderingMeal == meal.id ? "Fine riordino" : "Riordina") { orderingMeal = orderingMeal == meal.id ? nil : meal.id }.font(.caption).padding(.top, 6)
            }
            ForEach(meal.items) { item in
                if let food = store.data.food(item) {
                    let amounts = food.nutrients.scaled(item.quantity / 100)
                    Button { portion = PortionRoute(mealID: meal.id, food: food, item: item) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Divider().padding(.top, 7)
                            HStack { Text(food.name).font(.subheadline.bold()).foregroundStyle(.primary); Spacer(); Text(formatNumber(item.quantity) + " " + food.unit.rawValue).font(.caption).foregroundStyle(FitTheme.lime) }
                            Text("\(formatNumber(amounts.kcal)) kcal · P \(formatNumber(amounts.protein)) · G \(formatNumber(amounts.fat)) · C \(formatNumber(amounts.carbs))").font(.caption2).foregroundStyle(FitTheme.muted)
                        }
                    }.buttonStyle(.plain).contextMenu { Button("Rimuovi dal pasto", systemImage: "trash", role: .destructive) { removal = MealRemoval(mealID: meal.id, itemID: item.id) } }
                    if orderingMeal == meal.id {
                        HStack {
                            Button { moveItem(item.id, in: meal.id, by: -1) } label: { Label("Su", systemImage: "arrow.up") }
                                .disabled(meal.items.first?.id == item.id).accessibilityLabel("Sposta \(food.name) prima")
                            Button { moveItem(item.id, in: meal.id, by: 1) } label: { Label("Giù", systemImage: "arrow.down") }
                                .disabled(meal.items.last?.id == item.id).accessibilityLabel("Sposta \(food.name) dopo")
                            Spacer()
                        }.buttonStyle(.bordered).font(.caption)
                    }
                }
            }
            if meal.items.isEmpty { Text("Scegli gli alimenti per questo pasto.").font(.caption).foregroundStyle(FitTheme.muted).padding(.top, 8) }
        }
    }
    private func moveItem(_ itemID: UUID, in mealID: UUID, by offset: Int) {
        store.change { try $0.moveMealItem(date: date, base: base, mealID: mealID, itemID: itemID, offset: offset) }
    }
    private func removeSelected() {
        guard let removal else { return }
        store.delete(label: removal.itemID == nil ? "Spuntino eliminato" : "Alimento rimosso dal pasto") { data in data.editDiet(date, base: base) { day in
            if let itemID = removal.itemID, let m = day.meals.firstIndex(where: { $0.id == removal.mealID }) { day.meals[m].items.removeAll { $0.id == itemID } }
            else { day.meals.removeAll { $0.id == removal.mealID && $0.isSnack } }
        } }; self.removal = nil
    }
}
struct FoodPicker: View {
    let select: (Food) -> Void
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List(store.data.foods.filter { !$0.archived && $0.unit == .g && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }) { food in Button { select(food) } label: { VStack(alignment: .leading, spacing: 5) { Text(food.name).foregroundStyle(.primary); Text("\(formatNumber(food.nutrients.kcal)) kcal / 100 \(food.unit.rawValue)").font(.caption).foregroundStyle(FitTheme.muted) } } }.searchable(text: $query, prompt: "Cerca alimento").navigationTitle("Scegli alimento").toolbar { Button("Chiudi") { dismiss() } }
        }
    }
}
struct PortionEditor: View {
    let route: PortionRoute
    let date: Date
    let base: Bool
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = ""
    @State private var correctingFood = false
    private var legacy: Bool { route.food.unit == .ml }
    private var gramFood: Food? {
        legacy ? store.data.foods.first { $0.id == route.food.id && $0.unit == .g } : route.food
    }
    var body: some View {
        EditorFrame(title: route.food.name, save: save) {
            if legacy {
                Text("Quantità originale: \(formatNumber(route.item?.quantity ?? 0)) ml. Inserisci tu i grammi: il valore non viene convertito automaticamente.").font(.caption).foregroundStyle(.orange)
                if gramFood == nil { Button("Verifica alimento per 100 g") { correctingFood = true } }
                else { Text("Questa porzione userà i valori per 100 g verificati nel catalogo. Le altre porzioni restano invariate.").font(.caption) }
            }
            DecimalField(label: "Quantità in g", value: $quantity)
            if let food = gramFood, let number = try? Input.decimal(quantity, label: "Quantità", range: 0.0001...100000) {
                let totals = food.nutrients.scaled(number / 100)
                Text("\(formatNumber(totals.kcal)) kcal\nProteine \(formatNumber(totals.protein)) g\nGrassi \(formatNumber(totals.fat)) g\nCarboidrati \(formatNumber(totals.carbs)) g")
            }
            Text(base ? "Modifichi il programma settimanale di base." : "Modifichi soltanto questa data.").font(.caption)
        }.onAppear { quantity = legacy ? "" : editNumber(route.item?.quantity ?? 100) }
            .sheet(isPresented: $correctingFood) { FoodEditor(food: route.food) }
    }
    private func save() {
        do {
            let amount = try Input.decimal(quantity, label: "Quantità", range: 0.0001...100000)!
            if legacy {
                guard let food = gramFood, let item = route.item else { throw InputError.invalid("Prima verifica e salva i valori dell’alimento per 100 g.") }
                if store.change({ try $0.correctLegacyPortion(date: date, base: base, mealID: route.mealID, itemID: item.id, food: food, grams: amount) }) { dismiss() }
                return
            }
            if store.change({ data in data.editDiet(date, base: base) { day in
                guard let m = day.meals.firstIndex(where: { $0.id == route.mealID }) else { return }
                if let item = route.item, let i = day.meals[m].items.firstIndex(where: { $0.id == item.id }) { day.meals[m].items[i].quantity = amount }
                else { day.meals[m].items.append(MealItem(foodID: route.food.id, quantity: amount, snapshot: base ? nil : route.food)) }
            } }) { dismiss() }
        } catch { store.message = error.localizedDescription }
    }
}
struct FoodCatalogView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var create = false
    @State private var editor: Food? = nil
    @State private var removal: Food? = nil
    @State private var goals = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                FitCard { HStack { VStack(alignment: .leading, spacing: 6) { Text("Peso e obiettivi base").font(.headline); Text(store.data.bodyWeight.map { formatNumber($0) + " kg" } ?? "Peso da impostare").font(.caption).foregroundStyle(FitTheme.muted) }; Spacer(); Button("Imposta") { goals = true } }; Text("Gli stessi obiettivi per tutti i giorni.").font(.caption).foregroundStyle(FitTheme.muted).padding(.top, 10) }
                TextField("Cerca alimento", text: $query).textFieldStyle(.roundedBorder)
                Button("＋ Nuovo alimento") { create = true }.buttonStyle(PrimaryButtonStyle())
                Text("Valori per 100 g. Tieni premuto per eliminare.").font(.caption).foregroundStyle(FitTheme.muted)
                ForEach(store.data.foods.filter { (!$0.archived || $0.unit == .ml) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }) { food in
                    Button { editor = food } label: { FitCard { VStack(alignment: .leading, spacing: 7) { Text(food.name).font(.headline); Text("\(formatNumber(food.nutrients.kcal)) kcal / 100 \(food.unit.rawValue)").font(.caption).foregroundStyle(FitTheme.muted); Text("P \(formatNumber(food.nutrients.protein)) · G \(formatNumber(food.nutrients.fat)) · C \(formatNumber(food.nutrients.carbs))").font(.caption).foregroundStyle(FitTheme.muted) } } }.buttonStyle(.plain)
                        .contextMenu { Button("Modifica", systemImage: "pencil") { editor = food }; Button("Elimina dal catalogo", systemImage: "trash", role: .destructive) { removal = food } }
                }
            }.padding()
        }.sheet(isPresented: $create) { FoodEditor(food: Food(name: "", nutrients: Nutrients())) }.sheet(item: $editor) { FoodEditor(food: $0) }.sheet(isPresented: $goals) { GoalsEditor() }
            .alert("Eliminare dal catalogo?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) { Button("Annulla", role: .cancel) { removal = nil }; Button("Elimina", role: .destructive) { if let id = removal?.id { store.delete(label: "Alimento eliminato dal catalogo") { data in if let i = data.foods.firstIndex(where: { $0.id == id }) { data.foods[i].archived = true } } }; removal = nil } } message: { Text("Gli alimenti nei pasti restano disponibili.") }
    }
}
struct FoodEditor: View {
    let food: Food
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var carbs = ""
    @State private var gramValuesReviewed = false

    init(food: Food) {
        self.food = food
    }
    var body: some View {
        EditorFrame(title: "Alimento", save: save) {
            TextField("Nome · specifica crudo o cotto", text: $name)
            Text("Valori nutrizionali riferiti a 100 g, anche per gli alimenti liquidi.").font(.caption)
            if food.unit == .ml {
                Text("I valori originali erano per 100 ml. Verifica i campi sotto prima di salvarli per 100 g. Le quantità nei pasti resteranno da correggere separatamente.").font(.caption).foregroundStyle(.orange)
                Toggle("Ho verificato i valori per 100 g", isOn: $gramValuesReviewed)
            }
            DecimalField(label: "Kcal", value: $kcal); DecimalField(label: "Proteine (g)", value: $protein); DecimalField(label: "Grassi (g)", value: $fat); DecimalField(label: "Carboidrati (g)", value: $carbs)
            Section("Fonte") { Text(food.source).font(.caption); if let url = try? Input.webURL(food.sourceURL) { Link("Consulta fonte ↗", destination: url) }; Text("Le kcal restano quelle della fonte o dell’etichetta. Modificare i valori aggiorna la base; le date personalizzate conservano la propria copia.").font(.caption) }
        }.onAppear { name = food.name; kcal = editNumber(food.nutrients.kcal); protein = editNumber(food.nutrients.protein); fat = editNumber(food.nutrients.fat); carbs = editNumber(food.nutrients.carbs) }
    }
    private func save() {
        do {
            guard food.unit == .g || gramValuesReviewed else { throw InputError.invalid("Verifica i valori nutrizionali per 100 g e seleziona la conferma.") }
            var draft = food
            draft.name = try Input.text(name, label: "Nome", limit: 100)
            draft.unit = .g
            draft.nutrients = try Nutrients(kcal: Input.decimal(kcal, label: "Kcal", range: 0...10000)!, protein: Input.decimal(protein, label: "Proteine", range: 0...10000)!, fat: Input.decimal(fat, label: "Grassi", range: 0...10000)!, carbs: Input.decimal(carbs, label: "Carboidrati", range: 0...10000)!)
            if draft.nutrients != food.nutrients || draft.unit != food.unit { draft.source = "Valori personalizzati dall’utente"; draft.sourceURL = "" }
            if store.change({ try $0.saveGramFood(draft) }) { dismiss() }
        } catch { store.message = error.localizedDescription }
    }
}
struct GoalDraft { var kcal = "", protein = "", fat = "", carbs = "" }
struct GoalsEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var weight = ""
    @State private var draft = GoalDraft()
    var body: some View {
        EditorFrame(title: "Obiettivi della dieta base", save: save) {
            DecimalField(label: "Peso corporeo (kg)", value: $weight)
            DecimalField(label: "Kcal al giorno", value: $draft.kcal)
            DecimalField(label: "Proteine (g/kg)", value: $draft.protein)
            DecimalField(label: "Grassi (g/kg)", value: $draft.fat)
            DecimalField(label: "Carboidrati (g/kg)", value: $draft.carbs)
            Section("Obiettivi in grammi") { preview }
            Text("Questi obiettivi valgono per tutti i giorni, anche quelli con pasti personalizzati. Kcal e macro sono indipendenti. Lascia vuoti quelli che non vuoi impostare.").font(.caption)
        }.onAppear {
            weight = editNumber(store.data.bodyWeight)
            let goals = store.data.baseGoals
            draft = GoalDraft(kcal: editNumber(goals.kcal), protein: editNumber(goals.proteinPerKg), fat: editNumber(goals.fatPerKg), carbs: editNumber(goals.carbsPerKg))
        }
    }
    private func parsed(_ draft: GoalDraft) throws -> Goals {
        try Goals(kcal: Input.decimal(draft.kcal, label: "Kcal", range: 0...Double.greatestFiniteMagnitude, optional: true), proteinPerKg: Input.decimal(draft.protein, label: "Proteine g/kg", range: 0...Double.greatestFiniteMagnitude, optional: true), fatPerKg: Input.decimal(draft.fat, label: "Grassi g/kg", range: 0...Double.greatestFiniteMagnitude, optional: true), carbsPerKg: Input.decimal(draft.carbs, label: "Carboidrati g/kg", range: 0...Double.greatestFiniteMagnitude, optional: true))
    }
    private var preview: some View {
        let result: Result<Targets, Error> = Result { let w = try Input.decimal(weight, label: "Peso", range: 0.1...500, optional: true); return try parsed(draft).targets(weight: w) }
        return Group {
            switch result {
            case .success(let targets):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Proteine: \(targets.protein.map { formatNumber($0) + " g" } ?? "—")")
                    Text("Grassi: \(targets.fat.map { formatNumber($0) + " g" } ?? "—")")
                    Text("Carboidrati: \(targets.carbs.map { formatNumber($0) + " g" } ?? "—")").foregroundStyle(FitTheme.lime)
                }
            case .failure(let error): Text(error.localizedDescription).foregroundStyle(.orange)
            }
        }
    }
    private func save() {
        do {
            let weight = try Input.decimal(weight, label: "Peso", range: 0.1...500, optional: true)
            let goals = try parsed(draft)
            _ = try goals.targets(weight: weight)
            if store.change({ $0.setBaseGoals(goals, weight: weight) }) { dismiss() }
        } catch { store.message = error.localizedDescription }
    }
}

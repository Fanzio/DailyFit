import SwiftUI

struct DietCopyEditor: View {
    let route: DietCopyRoute
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var mealID: UUID? = nil
    @State private var confirm = false
    private var destination: DietDay { store.data.diet(date, base: route.base) }

    var body: some View {
        EditorFrame(title: route.meal == nil ? "Copia pasti" : "Copia pasto", save: requestSave) {
            Section("Destinazione") {
                if route.base {
                    Picker("Giorno della dieta base", selection: Binding(get: { Dates.weekday(date) }, set: { date = Dates.inWeek(date, weekday: $0) })) {
                        ForEach(0..<7) { Text(Dates.names[$0]).tag($0) }
                    }
                } else {
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                }
                if route.meal != nil {
                    Picker("Pasto", selection: $mealID) {
                        ForEach(destination.meals) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            Section {
                if let meal = route.meal { Text("\(meal.name): \(meal.items.count) alimenti da copiare.") }
                else { Text("Copi \(route.source.meals.count) pasti con quantità e alimenti.") }
                Text(route.base ? "La destinazione fa parte della dieta base settimanale." : "La copia modifica solo la data scelta.")
                Text("Gli obiettivi restano quelli comuni della dieta base.")
            }.font(.caption)
        }
        .onAppear {
            date = Dates.shifting(route.date, days: 1)
            selectMeal()
        }
        .onChange(of: date) { _, _ in selectMeal() }
        .alert("Sostituire i cibi presenti?", isPresented: $confirm) {
            Button("Annulla", role: .cancel) {}
            Button("Sostituisci", role: .destructive) { save() }
        } message: { Text("I cibi della destinazione verranno sostituiti dalla copia. Il giorno di origine resta disponibile.") }
    }

    private func selectMeal() {
        mealID = destination.meals.first(where: { $0.name == route.meal?.name })?.id ?? destination.meals.first?.id
    }

    private func requestSave() {
        let existing = route.meal == nil ? destination.meals.flatMap(\.items) : destination.meals.first(where: { $0.id == mealID })?.items ?? []
        if existing.isEmpty { save() } else { confirm = true }
    }

    private func save() {
        let success = store.change { data in
            if let meal = route.meal {
                guard let mealID else { throw InputError.invalid("Scegli un pasto di destinazione.") }
                try data.copyMeal(from: meal, date: date, base: route.base, destinationID: mealID)
            } else {
                try data.copyDietMeals(from: route.source, date: date, base: route.base)
            }
        }
        if success { dismiss() }
    }
}

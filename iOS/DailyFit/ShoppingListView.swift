import SwiftUI

struct ShoppingListView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var total = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Le quantità dei sette giorni della dieta base, da lunedì a domenica. Le modifiche delle singole date non cambiano questa lista.").font(.caption).foregroundStyle(FitTheme.muted)
                    Picker("Raggruppamento", selection: $total) {
                        Text("Per pasto").tag(false)
                        Text("Totale settimana").tag(true)
                    }.pickerStyle(.segmented)
                }
                if ShoppingList.sections(for: store.data).isEmpty {
                    Section { Text("Aggiungi alimenti alla dieta base per creare la lista della spesa.").foregroundStyle(FitTheme.muted) }
                } else if total {
                    Section("Totale da acquistare") { ForEach(ShoppingList.totals(for: store.data)) { row($0) } }
                } else {
                    ForEach(ShoppingList.sections(for: store.data)) { section in
                        Section(section.id.rawValue) { ForEach(section.items) { row($0) } }
                    }
                    Section { Text("Lo stesso alimento può comparire in più pasti. Apri Totale settimana per vedere quanto acquistarne complessivamente.").font(.caption).foregroundStyle(FitTheme.muted) }
                }
            }
            .scrollContentBackground(.hidden).background(FitTheme.background)
            .navigationTitle("Lista della spesa").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
    }

    private func row(_ item: ShoppingItem) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(item.name)
            Spacer(minLength: 12)
            Text(amount(item.quantity) + " " + item.unit.rawValue)
                .fontWeight(.semibold).foregroundStyle(FitTheme.lime).multilineTextAlignment(.trailing)
        }.padding(.vertical, 4)
    }
    private func amount(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "it_IT")).precision(.fractionLength(0...4)))
    }
}

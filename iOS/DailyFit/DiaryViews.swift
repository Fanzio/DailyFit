import SwiftUI

struct NotesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var editor: DiaryNote? = nil
    @State private var removal: DiaryNote? = nil
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("Il tuo spazio per appunti, carichi e idee.").font(.caption).foregroundStyle(FitTheme.muted)
                TextField("Cerca nelle note", text: $query).textFieldStyle(.roundedBorder)
                Button("＋ Nuova nota") { editor = DiaryNote() }.buttonStyle(PrimaryButtonStyle())
                ForEach(store.data.notes.filter { query.isEmpty || ($0.title + "\n" + $0.body).localizedCaseInsensitiveContains(query) }.sorted { $0.updatedAt > $1.updatedAt }) { note in
                    Button { editor = note } label: { FitCard { VStack(alignment: .leading, spacing: 8) { Text(note.displayTitle).font(.headline).lineLimit(1); Text(String(note.body.prefix(240))).font(.subheadline).lineLimit(2).foregroundStyle(FitTheme.muted); Text(note.updatedAt, format: .dateTime.day().month().year().hour().minute()).font(.caption2).foregroundStyle(FitTheme.muted) } } }.buttonStyle(.plain)
                        .contextMenu { Button("Elimina nota", systemImage: "trash", role: .destructive) { removal = note } }
                }
            }.padding()
        }.sheet(item: $editor) { NoteEditor(note: $0) }
            .alert("Eliminare la nota?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) { Button("Annulla", role: .cancel) { removal = nil }; Button("Elimina", role: .destructive) { if let id = removal?.id { store.delete(label: "Nota eliminata") { $0.notes.removeAll { $0.id == id } } }; removal = nil } }
    }
}
struct NoteEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DiaryNote
    init(note: DiaryNote) { _draft = State(initialValue: note) }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Titolo", text: $draft.title).font(.title2.bold())
                Text(draft.updatedAt, format: .dateTime.day().month().year().hour().minute()).font(.caption).foregroundStyle(FitTheme.muted)
                TextEditor(text: $draft.body).scrollContentBackground(.hidden).accessibilityLabel("Testo della nota")
            }.padding().background(FitTheme.background).navigationTitle("Diario").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Fine") { if save() { dismiss() } } }
                .onChange(of: draft.title) { _, _ in save() }.onChange(of: draft.body) { _, _ in save() }
                .onAppear { store.editorCount += 1 }
                .onDisappear { save(); store.editorCount = max(0, store.editorCount - 1) }
        }
        .interactiveDismissDisabled(draft.title.count > 120 || draft.body.count > 200000)
        .alert("DailyFit", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("OK") { store.message = nil } } message: { Text(store.message ?? "") }
    }
    @discardableResult
    private func save() -> Bool {
        guard draft.title.count <= 120, draft.body.count <= 200000 else { store.message = "La nota supera il limite: titolo 120 caratteri, testo 200.000."; return false }
        if let saved = store.data.notes.first(where: { $0.id == draft.id }), saved.title == draft.title && saved.body == draft.body { return true }
        draft.updatedAt = Date(); return store.saveNote(draft)
    }
}

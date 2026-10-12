import SwiftUI
import UniformTypeIdentifiers

struct ExportDocument: FileDocument {
    static let excel = UTType(filenameExtension: "xlsx") ?? UTType(importedAs: "org.openxmlformats.spreadsheetml.sheet")
    static var readableContentTypes: [UTType] { [.json, excel] }
    let bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.bytes = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var rest: RestController
    @EnvironmentObject private var navigation: NavigationState
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var exporting = false
    @State private var importing = false
    @State private var confirmRestore = false
    @State private var imported: AppData? = nil
    @State private var document: ExportDocument? = nil
    @State private var exportType = UTType.json
    @State private var filename = "DailyFit-backup"

    var body: some View {
        NavigationStack {
            Form {
                Section("Allenamento") {
                    Toggle("Mantieni lo schermo acceso", isOn: Binding(get: { store.data.keepScreenAwake == true }, set: { enabled in store.change { $0.keepScreenAwake = enabled } }))
                    Text("Solo mentre consulti una giornata di allenamento. Uscendo dalla palestra o mettendo l’app in background torna il blocco automatico.").font(.caption)
                }
                Section("Backup completo") {
                    Button("Esporta backup JSON") { prepareExport(excel: false) }
                    Button("Ripristina da backup") { importing = true }
                    Text("Conserva schede, esercizi, immagini, appunti, alimenti, dieta, obiettivi e impostazioni. Il ripristino sostituisce i dati dell’app dopo la tua conferma.").font(.caption)
                }
                Section("Google Fogli / Excel") {
                    Button("Esporta tutto in Excel (.xlsx)") { prepareExport(excel: true) }
                    Text("Il file contiene più fogli con tutti i dati consultabili. In Google Fogli scegli File → Importa → Carica. Le immagini sono conservate nel backup JSON.").font(.caption)
                    Text("Puoi salvare i file in Su iPhone per tenerli locali. Scegliere Drive o iCloud li salva nel servizio che selezioni.").font(.caption)
                }
                if busy { Section { ProgressView(store.restoring ? "Ripristino…" : "Preparazione file…") } }
            }
            .disabled(busy)
            .scrollContentBackground(.hidden).background(FitTheme.background)
            .navigationTitle("Impostazioni e backup").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() }.disabled(busy) } }
        }
        .interactiveDismissDisabled(busy)
        .onAppear { store.editorCount += 1 }
        .onDisappear { store.editorCount = max(0, store.editorCount - 1) }
        .fileExporter(isPresented: $exporting, document: document, contentType: exportType, defaultFilename: filename) { result in
            document = nil
            if case .failure(let error) = result { show(error) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): readBackup(url)
            case .failure(let error): show(error)
            }
        }
        .alert("Sostituire i dati con il backup?", isPresented: $confirmRestore) {
            Button("Annulla", role: .cancel) { imported = nil }
            Button("Ripristina", role: .destructive) { restore() }
        } message: {
            if let imported { Text("Il backup contiene \(imported.plans.count) schede, \(imported.exercises.count) esercizi, \(imported.notes.count) note e \(imported.foods.count) alimenti. Verranno sostituiti tutti i dati attuali. Il timer resterà fermo.") }
        }
        .alert("DailyFit", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: { Text(store.message ?? "") }
    }

    private func prepareExport(excel: Bool) {
        guard !busy else { return }
        busy = true
        let snapshot = store.data
        Task {
            do {
                let exportData = excel ? snapshot : try await store.exportSnapshot(snapshot)
                let bytes = try await Task.detached(priority: .userInitiated) {
                    if excel { return try SpreadsheetExport.encode(snapshot) }
                    return try BackupCodec.encode(exportData)
                }.value
                document = ExportDocument(bytes: bytes)
                exportType = excel ? ExportDocument.excel : .json
                filename = "DailyFit-" + (excel ? "dati-" : "backup-") + Dates.key(Date())
                exporting = true
            } catch { show(error) }
            busy = false
        }
    }

    private func readBackup(_ url: URL) {
        busy = true
        Task {
            do {
                imported = try await Task.detached(priority: .userInitiated) { try LocalRepository.readBackup(url) }.value
                confirmRestore = true
            } catch { show(error) }
            busy = false
        }
    }

    private func restore() {
        guard let imported else { return }
        busy = true
        Task {
            if await store.restoreBackup(imported) {
                rest.stop()
                navigation.resetAfterRestore()
                store.message = "Backup ripristinato."
            }
            self.imported = nil
            busy = false
        }
    }

    private func show(_ error: Error) {
        if (error as NSError).code != NSUserCancelledError { store.message = error.localizedDescription }
    }
}

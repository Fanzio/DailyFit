import SwiftUI
import PhotosUI
import ImageIO

struct GymView: View {
    @EnvironmentObject private var navigation: NavigationState
    @State private var settings = false
    var body: some View {
        NavigationStack(path: $navigation.gymPath) {
            VStack(spacing: 0) {
                Picker("Sezioni palestra", selection: $navigation.gymSection) { Text("Schede").tag(0); Text("Esercizi").tag(1); Text("Diario").tag(2) }.pickerStyle(.segmented).padding()
                ZStack {
                    PlansView().opacity(navigation.gymSection == 0 ? 1 : 0).allowsHitTesting(navigation.gymSection == 0).accessibilityHidden(navigation.gymSection != 0)
                    ExerciseCatalogView().opacity(navigation.gymSection == 1 ? 1 : 0).allowsHitTesting(navigation.gymSection == 1).accessibilityHidden(navigation.gymSection != 1)
                    NotesView().opacity(navigation.gymSection == 2 ? 1 : 0).allowsHitTesting(navigation.gymSection == 2).accessibilityHidden(navigation.gymSection != 2)
                }
            }.background(FitTheme.background).navigationTitle("Palestra").navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: GymRoute.self) { route in
                    switch route {
                    case .plan(let id): PlanDaysView(planID: id)
                    case .day(let planID, let dayID): TrainingDayView(planID: planID, dayID: dayID)
                    }
                }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Impostazioni e backup") } }
                .sheet(isPresented: $settings) { SettingsView() }
        }
    }
}
struct NameEditor: View {
    let title: String
    let initial: String
    let onSave: (String) -> Bool
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    var body: some View {
        EditorFrame(title: title, save: {
            do { let clean = try Input.text(name, label: "Nome", limit: 80); if onSave(clean) { dismiss() } } catch { store.message = error.localizedDescription }
        }) { TextField("Nome", text: $name) }.onAppear { name = initial }
    }
}
struct PlansView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var rest: RestController
    @State private var create = false
    @State private var rename: TrainingPlan? = nil
    @State private var removal: TrainingPlan? = nil
    @State private var duplicate: TrainingPlan? = nil
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("Le tue schede").font(.title3.bold())
                Text("Tieni premuto per rinominare, duplicare o eliminare.").font(.caption).foregroundStyle(FitTheme.muted)
                ForEach(store.data.plans) { plan in
                    NavigationLink(value: GymRoute.plan(plan.id)) { FitCard { HStack { Image(systemName: "rectangle.stack").foregroundStyle(FitTheme.lime); VStack(alignment: .leading, spacing: 6) { Text(plan.name).font(.headline); Text("\(plan.days.count) giornate").font(.caption).foregroundStyle(FitTheme.muted) }; Spacer(); Image(systemName: "chevron.right").font(.caption) } } }.buttonStyle(.plain)
                        .contextMenu { Button("Rinomina", systemImage: "pencil") { rename = plan }; Button("Duplica scheda", systemImage: "doc.on.doc") { duplicate = plan }; Button("Elimina", systemImage: "trash", role: .destructive) { removal = plan } }
                }
                if store.data.plans.isEmpty { Text("Crea la tua prima scheda.").foregroundStyle(FitTheme.muted) }
                Button("＋ Crea una nuova scheda") { create = true }.buttonStyle(PrimaryButtonStyle())
            }.padding()
        }
        .sheet(isPresented: $create) { NameEditor(title: "Nuova scheda", initial: "") { name in store.change { $0.plans.append(TrainingPlan(name: name)) } } }
        .sheet(item: $rename) { plan in NameEditor(title: "Rinomina scheda", initial: plan.name) { name in store.change { data in if let i = data.plans.firstIndex(where: { $0.id == plan.id }) { data.plans[i].name = name } } } }
        .sheet(item: $duplicate) { plan in NameEditor(title: "Duplica scheda", initial: String(plan.name.prefix(72)) + " · copia") { name in store.change { try $0.duplicatePlan(plan.id, name: name) } } }
        .alert("Eliminare la scheda e tutte le sue giornate?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
            Button("Annulla", role: .cancel) { removal = nil }
            Button("Elimina", role: .destructive) {
                guard let plan = removal else { return }
                if plan.days.flatMap(\.entries).contains(where: { $0.id == store.data.timer?.entryID }) { rest.stop() }
                store.delete(label: "Scheda eliminata") { $0.plans.removeAll { $0.id == plan.id } }; removal = nil
            }
        }
    }
}
struct PlanDaysView: View {
    let planID: UUID
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var rest: RestController
    @State private var create = false
    @State private var rename: TrainingDay? = nil
    @State private var removal: TrainingDay? = nil
    @State private var duplicate: TrainingDay? = nil
    private var plan: TrainingPlan? { store.data.plans.first { $0.id == planID } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let plan {
                    ForEach(plan.days) { day in
                        NavigationLink(value: GymRoute.day(planID, day.id)) { FitCard { HStack { VStack(alignment: .leading, spacing: 6) { Text(day.name).font(.headline); Text("\(day.entries.count) esercizi · \(day.entries.reduce(0) { $0 + $1.sets.count }) serie").font(.caption).foregroundStyle(FitTheme.muted) }; Spacer(); Image(systemName: "chevron.right") } } }.buttonStyle(.plain)
                            .contextMenu { Button("Rinomina", systemImage: "pencil") { rename = day }; Button("Duplica giornata", systemImage: "doc.on.doc") { duplicate = day }; Button("Elimina", systemImage: "trash", role: .destructive) { removal = day } }
                    }
                    if plan.days.isEmpty { Text("Aggiungi la prima giornata.").foregroundStyle(FitTheme.muted) }
                    Button("＋ Aggiungi giornata") { create = true }.buttonStyle(PrimaryButtonStyle())
                }
            }.padding()
        }.background(FitTheme.background).navigationTitle(plan?.name ?? "Scheda").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $create) { NameEditor(title: "Nuova giornata", initial: "") { name in store.change { data in if let p = data.plans.firstIndex(where: { $0.id == planID }) { data.plans[p].days.append(TrainingDay(name: name)) } } } }
            .sheet(item: $rename) { day in NameEditor(title: "Rinomina giornata", initial: day.name) { name in editDay(day.id) { $0.name = name } } }
            .sheet(item: $duplicate) { day in NameEditor(title: "Duplica giornata", initial: String(day.name.prefix(72)) + " · copia") { name in store.change { try $0.duplicateDay(planID: planID, dayID: day.id, name: name) } } }
            .alert("Eliminare la giornata e i suoi esercizi?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
                Button("Annulla", role: .cancel) { removal = nil }
                Button("Elimina", role: .destructive) {
                    guard let day = removal else { return }
                    if day.entries.contains(where: { $0.id == store.data.timer?.entryID }) { rest.stop() }
                    store.delete(label: "Giornata eliminata") { data in if let p = data.plans.firstIndex(where: { $0.id == planID }) { data.plans[p].days.removeAll { $0.id == day.id } } }; removal = nil
                }
            }
    }
    private func editDay(_ id: UUID, edit: (inout TrainingDay) -> Void) -> Bool {
        store.change { data in if let p = data.plans.firstIndex(where: { $0.id == planID }), let d = data.plans[p].days.firstIndex(where: { $0.id == id }) { edit(&data.plans[p].days[d]) } }
    }
}
struct TrainingDayView: View {
    let planID: UUID
    let dayID: UUID
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var rest: RestController
    @State private var choose = false
    @State private var edit: TrainingEntry? = nil
    @State private var detail: Exercise? = nil
    @State private var removal: TrainingEntry? = nil
    private var day: TrainingDay? { store.data.plans.first { $0.id == planID }?.days.first { $0.id == dayID } }
    var body: some View {
        List {
            ForEach(day?.entries ?? []) { entry in
                if let exercise = store.data.exercise(entry.exerciseID) {
                    FitCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(entry.displayName(for: exercise)).font(.headline)
                                Spacer(minLength: 0)
                                Button("Modifica") { edit = entry }.font(.caption).fixedSize()
                                    .accessibilityLabel("Modifica serie di " + entry.displayName(for: exercise))
                            }
                            HStack(alignment: .center, spacing: 12) {
                                Button { detail = exercise } label: {
                                    VStack(spacing: 4) {
                                        ExercisePicture(exercise: exercise)
                                        Text("Dettagli").font(.caption2).foregroundStyle(FitTheme.lime)
                                    }
                                }.buttonStyle(.plain).accessibilityLabel("Dettagli di " + exercise.name)
                                Grid(horizontalSpacing: 10, verticalSpacing: 6) {
                                    GridRow {
                                        Text("SERIE")
                                        Text(entry.sets.allSatisfy { $0.effectiveUnit == .seconds } ? "DURATA" : "RIP.")
                                        Text("CARICO")
                                    }.font(.caption2).foregroundStyle(FitTheme.muted)
                                    ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                                        GridRow {
                                            Text("\(index + 1)")
                                            Text(set.displayTarget)
                                            Text(formatNumber(set.load) + " kg")
                                        }.font(.subheadline.monospacedDigit())
                                    }
                                }.lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
                            }
                            Divider()
                            HStack {
                                InlineRestTime(entry: entry)
                                Spacer()
                                Button(timerAction(entry)) { if store.data.timer?.entryID == entry.id { rest.toggle() } else { rest.start(entry, name: entry.displayName(for: exercise)) } }.buttonStyle(.bordered).tint(FitTheme.lime)
                                Button { rest.start(entry, name: entry.displayName(for: exercise)) } label: { Image(systemName: "arrow.counterclockwise") }.accessibilityLabel("Riavvia recupero")
                            }
                        }
                    }.contextMenu { Button("Modifica serie e recupero", systemImage: "pencil") { edit = entry }; Button("Rimuovi dalla giornata", systemImage: "trash", role: .destructive) { removal = entry } }
                        .listRowSeparator(.hidden).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }.onMove { from, to in mutateDay { $0.entries.move(fromOffsets: from, toOffset: to) } }
            Button("＋ Aggiungi esercizio") { choose = true }.buttonStyle(PrimaryButtonStyle()).listRowBackground(Color.clear).listRowSeparator(.hidden)
        }.listStyle(.plain).scrollContentBackground(.hidden).background(FitTheme.background).navigationTitle(day?.name ?? "Giornata").navigationBarTitleDisplayMode(.inline)
            .toolbar { EditButton() }
            .sheet(isPresented: $choose) { ExercisePicker { exercise in mutateDay { $0.entries.append(TrainingEntry(exerciseID: exercise.id)) }; choose = false } }
            .sheet(item: $edit) { entry in SetsEditor(entry: entry) }
            .sheet(item: $detail) { exercise in ExerciseDetail(exerciseID: exercise.id) }
            .alert("Rimuovere l’esercizio da questa giornata?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
                Button("Annulla", role: .cancel) { removal = nil }
                Button("Rimuovi", role: .destructive) {
                    if let entry = removal {
                        if store.data.timer?.entryID == entry.id { rest.stop() }
                        store.delete(label: "Esercizio rimosso") { data in
                            if let p = data.plans.firstIndex(where: { $0.id == planID }), let d = data.plans[p].days.firstIndex(where: { $0.id == dayID }) {
                                data.plans[p].days[d].entries.removeAll { $0.id == entry.id }
                            }
                        }
                    }
                    removal = nil
                }
            }
    }
    private func mutateDay(_ edit: (inout TrainingDay) -> Void) {
        store.change { data in if let p = data.plans.firstIndex(where: { $0.id == planID }), let d = data.plans[p].days.firstIndex(where: { $0.id == dayID }) { edit(&data.plans[p].days[d]) } }
    }
    private func timerAction(_ entry: TrainingEntry) -> String {
        guard let timer = store.data.timer, timer.entryID == entry.id else { return "Avvia" }
        return timer.remaining() == 0 ? "Riavvia" : timer.running ? "Pausa" : "Riprendi"
    }
}
struct InlineRestTime: View {
    let entry: TrainingEntry
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var navigation: NavigationState
    @Environment(\.scenePhase) private var phase
    var body: some View {
        if let timer = store.data.timer, timer.entryID == entry.id {
            if timer.running && phase == .active && navigation.area == 0 {
                TimelineView(.periodic(from: .now, by: 1)) { context in Label(timerText(timer.remaining(at: context.date)), systemImage: "timer").font(.headline.monospacedDigit()) }
            } else { Label(timerText(timer.remaining()), systemImage: "timer").font(.headline.monospacedDigit()) }
        } else { Label(timerText(entry.rest), systemImage: "timer").font(.headline.monospacedDigit()) }
    }
}
struct SetDraft: Identifiable { var id: UUID; var reps: String; var load: String; var unit: TrainingSetUnit }
struct SetsEditor: View {
    let entry: TrainingEntry
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [SetDraft] = []
    @State private var rest = "90"
    @State private var name = ""
    var body: some View {
        EditorFrame(title: "Serie e recupero", save: save) {
            DisclosureGroup("Nome nella giornata") {
                TextField("Usa il nome del catalogo", text: $name)
            }
            Section("Ogni serie può avere valori diversi") {
                ForEach($rows) { $row in
                    HStack(spacing: 10) {
                        Text("\((rows.firstIndex { $0.id == row.id } ?? 0) + 1)")
                            .foregroundStyle(FitTheme.muted).frame(minWidth: 16)
                        VStack(alignment: .leading, spacing: 7) {
                            Menu {
                                Picker("Misura", selection: $row.unit) {
                                    Text("Ripetizioni").tag(TrainingSetUnit.repetitions)
                                    Text("Secondi").tag(TrainingSetUnit.seconds)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(row.unit == .seconds ? "Secondi" : "Ripetizioni")
                                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                                }.font(.caption)
                            }.buttonStyle(.borderless)
                                .accessibilityLabel("Unità della serie \((rows.firstIndex { $0.id == row.id } ?? 0) + 1)")
                                .accessibilityValue(row.unit == .seconds ? "Secondi" : "Ripetizioni")
                            TextField("8 o 12–20", text: $row.reps).keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel(row.unit == .seconds ? "Durata in secondi" : "Ripetizioni")
                        }
                        DecimalField(label: "Kg", value: $row.load)
                        Button(role: .destructive) { let id = row.id; if rows.count > 1 { rows.removeAll { $0.id == id } } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).disabled(rows.count == 1).accessibilityLabel("Rimuovi serie")
                    }
                }
                Button("Aggiungi serie") { if rows.count < 30 { rows.append(SetDraft(id: UUID(), reps: rows.last?.reps ?? "10", load: rows.last?.load ?? "0", unit: rows.last?.unit ?? .repetitions)) } }.disabled(rows.count >= 30)
            }
            Section { DecimalField(label: "Recupero in secondi", value: $rest) }
        }.onAppear { rows = entry.sets.map { SetDraft(id: $0.id, reps: $0.targetText, load: editNumber($0.load), unit: $0.effectiveUnit) }; rest = String(entry.rest); name = entry.nameOverride ?? "" }
    }
    private func save() {
        do {
            let sets = try rows.map { row -> TrainingSet in
                let target = try TrainingSet.parseTarget(row.reps, unit: row.unit)
                let load = try Input.decimal(row.load, label: "Carico", range: 0...2000)!
                return TrainingSet(id: row.id, reps: target.lower, load: load, upperReps: target.upper, unit: row.unit)
            }
            let seconds = try Input.decimal(rest, label: "Recupero", range: 1...3600)!
            guard seconds.rounded() == seconds else { throw InputError.invalid("Il recupero deve essere in secondi interi.") }
            let cleanName = try Input.text(name, label: "Nome nella giornata", limit: 80, required: false)
            if store.change({ data in
                for p in data.plans.indices { for d in data.plans[p].days.indices {
                    if let e = data.plans[p].days[d].entries.firstIndex(where: { $0.id == entry.id }) {
                        data.plans[p].days[d].entries[e].sets = sets
                        data.plans[p].days[d].entries[e].rest = Int(seconds)
                        data.plans[p].days[d].entries[e].nameOverride = cleanName.isEmpty ? nil : cleanName
                        return
                    }
                } }
                throw InputError.invalid("L’esercizio non è più disponibile nella giornata.")
            }) { dismiss() }
        } catch { store.message = error.localizedDescription }
    }
}
struct ExerciseCatalogView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var group = "Tutti"
    @State private var create = false
    @State private var edit: Exercise? = nil
    @State private var detail: Exercise? = nil
    @State private var removal: Exercise? = nil
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                TextField("Cerca un esercizio", text: $query).textFieldStyle(.roundedBorder)
                Picker("Gruppo muscolare", selection: $group) { Text("Tutti").tag("Tutti"); ForEach(Exercise.groups, id: \.self) { Text($0).tag($0) } }
                Button("＋ Nuovo esercizio") { create = true }.buttonStyle(PrimaryButtonStyle())
                ForEach(store.data.exercises.filter { !$0.archived && (group == "Tutti" || $0.muscle == group) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }) { exercise in
                    Button { detail = exercise } label: { ExerciseRow(exercise: exercise) }.buttonStyle(.plain)
                        .contextMenu { Button("Modifica", systemImage: "pencil") { edit = exercise }; Button("Elimina dal catalogo", systemImage: "trash", role: .destructive) { removal = exercise } }
                }
            }.padding()
        }
        .sheet(isPresented: $create) { ExerciseEditor(exercise: Exercise(name: "", muscle: "Petto", execution: "")) }
        .sheet(item: $edit) { ExerciseEditor(exercise: $0) }
        .sheet(item: $detail) { ExerciseDetail(exerciseID: $0.id) }
        .alert("Eliminare dal catalogo?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
            Button("Annulla", role: .cancel) { removal = nil }
            Button("Elimina", role: .destructive) { if let id = removal?.id { store.delete(label: "Esercizio eliminato dal catalogo") { data in if let i = data.exercises.firstIndex(where: { $0.id == id }) { data.exercises[i].archived = true } } }; removal = nil }
        } message: { Text("L’esercizio resterà nelle schede già create.") }
    }
}
struct ExerciseRow: View {
    let exercise: Exercise
    var body: some View { FitCard { HStack { ExercisePicture(exercise: exercise); VStack(alignment: .leading, spacing: 6) { Text(exercise.name).font(.headline); Text(exercise.muscle).font(.caption).foregroundStyle(FitTheme.muted) }; Spacer(); Image(systemName: "chevron.right").font(.caption) } } }
}
struct ExercisePicker: View {
    let select: (Exercise) -> Void
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        NavigationStack { List(store.data.exercises.filter { !$0.archived && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }) { exercise in Button { select(exercise) } label: { HStack { ExercisePicture(exercise: exercise); Text(exercise.name).foregroundStyle(.primary) } } }.searchable(text: $query, prompt: "Cerca esercizio").navigationTitle("Scegli esercizio").toolbar { Button("Chiudi") { dismiss() } } }
    }
}
struct ExerciseDetail: View {
    let exerciseID: UUID
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var edit = false
    var body: some View {
        NavigationStack {
            ScrollView {
                if let exercise = store.data.exercise(exerciseID) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(exercise.muscle).font(.caption).foregroundStyle(FitTheme.muted)
                        ExercisePicture(exercise: exercise, large: true)
                        if exercise.hasMusclePhoto {
                            Text("Muscoli coinvolti").font(.headline)
                            ExercisePicture(exercise: exercise, large: true, muscles: true)
                        }
                        Text("Come eseguirlo").font(.headline)
                        Text(exercise.execution.isEmpty ? "Descrizione da aggiungere." : exercise.execution)
                        Text("Video dimostrativo").font(.headline)
                        if let url = try? Input.webURL(exercise.video) { Link("Apri video ↗", destination: url) }
                        else { Text("Nessun video inserito.").foregroundStyle(FitTheme.muted) }
                    }.padding()
                        .navigationTitle(exercise.name)
                }
            }.background(FitTheme.background).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }; ToolbarItem(placement: .primaryAction) { Button("Modifica") { edit = true } } }
        }.sheet(isPresented: $edit) { if let exercise = store.data.exercise(exerciseID) { ExerciseEditor(exercise: exercise) } }
    }
}
struct ExerciseEditor: View {
    let exercise: Exercise
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Exercise
    @State private var photo: PhotosPickerItem? = nil
    @State private var muscleSelection: PhotosPickerItem? = nil
    @State private var loading = false
    @State private var loadingMuscles = false
    @State private var imageRevision = UUID()
    @State private var muscleImageRevision = UUID()
    init(exercise: Exercise) { self.exercise = exercise; _draft = State(initialValue: exercise) }
    var body: some View {
        EditorFrame(title: "Esercizio", save: save) {
            Section { TextField("Nome", text: $draft.name); Picker("Gruppo principale", selection: $draft.muscle) { ForEach(Exercise.groups, id: \.self) { Text($0) } } }
            Section("Immagine esecuzione facoltativa") { ExercisePicture(exercise: draft, large: true); PhotosPicker(selection: $photo, matching: .images) { Label(loading ? "Caricamento…" : "Scegli dal telefono", systemImage: "photo") }; Button("Rimuovi immagine") { photo = nil; draft.photo = nil; draft.photoFile = nil } }
            Section("Immagine muscoli facoltativa") {
                if draft.hasMusclePhoto { ExercisePicture(exercise: draft, large: true, muscles: true) }
                PhotosPicker(selection: $muscleSelection, matching: .images) { Label(loadingMuscles ? "Caricamento…" : "Scegli immagine dei muscoli", systemImage: "photo") }
                if draft.hasMusclePhoto { Button("Rimuovi immagine dei muscoli") { muscleSelection = nil; draft.musclePhoto = nil; draft.musclePhotoFile = nil } }
            }
            Section("Esecuzione") { TextEditor(text: $draft.execution).frame(minHeight: 130) }
            Section("Video facoltativo") { TextField("https://…", text: $draft.video).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled() }
        }
        .task(id: photo) { await loadPhoto(photo, muscles: false) }
        .task(id: muscleSelection) { await loadPhoto(muscleSelection, muscles: true) }
    }
    @MainActor
    private func loadPhoto(_ selection: PhotosPickerItem?, muscles: Bool) async {
        let token = UUID()
        if muscles { muscleImageRevision = token; loadingMuscles = selection != nil }
        else { imageRevision = token; loading = selection != nil }
        guard let selection else { return }
        defer {
            if muscles { if muscleImageRevision == token { loadingMuscles = false } }
            else if imageRevision == token { loading = false }
        }
        do {
            guard let bytes = try await selection.loadTransferable(type: Data.self), bytes.count <= 20_000_000 else { throw InputError.invalid("Scegli una foto inferiore a 20 MB.") }
            try Task.checkCancellation()
            let job = Task.detached(priority: .userInitiated) { try ImageProcessing.importJPEG(bytes) }
            let jpeg = try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { job.cancel() })
            try Task.checkCancellation()
            guard jpeg.count <= 2_000_000 else { throw InputError.invalid("Immagine troppo grande dopo l’importazione.") }
            if muscles { draft.musclePhoto = jpeg; draft.musclePhotoFile = nil } else { draft.photo = jpeg; draft.photoFile = nil }
        } catch is CancellationError { }
        catch { store.message = error.localizedDescription }
    }
    private func save() {
        guard !loading, !loadingMuscles else { store.message = "Attendi il caricamento delle immagini."; return }
        do {
            draft.name = try Input.text(draft.name, label: "Nome", limit: 80); try draft.validate()
            if store.change({ data in if let i = data.exercises.firstIndex(where: { $0.id == draft.id }) { data.exercises[i] = draft } else { data.exercises.append(draft) } }) { dismiss() }
        } catch { store.message = error.localizedDescription }
    }
}

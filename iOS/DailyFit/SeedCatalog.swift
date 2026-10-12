import Foundation

/// Original exercise descriptions. Food values transcribed from the cited CREA tables.
/// Versioned defaults are installed once, preserving personal edits and later deletions.
enum SeedCatalog {
    static let contentVersion = 1
    static func makeData(imageFolder: URL? = nil) -> AppData {
        var data = AppData()
        data.defaultContentVersion = contentVersion
        data.exercises = [
            exercise("Panca piana con bilanciere", muscle: "Petto", execution: "Spinta con bilanciere su panca piana. Dalla posizione con braccia estese, abbassa il bilanciere verso il petto e torna alla posizione iniziale con movimento controllato.", image: "01_panca_piana", folder: imageFolder),
            exercise("Squat con bilanciere", muscle: "Quadricipiti", execution: "Accosciata con bilanciere. Piega anche e ginocchia, poi torna in piedi mantenendo un movimento controllato e i piedi in appoggio.", image: "02_squat", folder: imageFolder),
            exercise("Trazioni supine", muscle: "Dorso", execution: "Trazioni alla sbarra con i palmi rivolti verso di te. Solleva il corpo flettendo i gomiti, poi torna alla posizione iniziale con controllo.", image: "03_trazioni_supine", folder: imageFolder),
            exercise("Stacco sumo", muscle: "Glutei", execution: "Stacco con bilanciere e posizione ampia dei piedi. Solleva il bilanciere estendendo anche e ginocchia, poi riportalo a terra con controllo.", image: "04_stacco_sumo", folder: imageFolder),
            exercise("Panca inclinata con manubri", muscle: "Petto", execution: "Spinte con manubri su panca inclinata. Porta i manubri all’altezza del petto, spingi verso l’alto e torna alla posizione iniziale con controllo.", image: "05_panca_inclinata", folder: imageFolder),
            exercise("Leg extension", muscle: "Quadricipiti", execution: "Estensione delle ginocchia alla macchina. Dalla posizione seduta, solleva il rullo estendendo le gambe e torna con controllo.", image: "06_leg_extension", folder: imageFolder),
            exercise("Lat machine stretta supina", muscle: "Dorso", execution: "Tirata alla lat machine con presa stretta e palmi rivolti verso di te. Porta la barra verso la parte alta del petto e lascia risalire il carico con controllo.", image: "07_lat_supina", folder: imageFolder),
            exercise("Leg curl sdraiato", muscle: "Femorali", execution: "Flessione delle ginocchia alla macchina da sdraiato. Porta il rullo verso i glutei e torna alla posizione iniziale mantenendo il corpo in appoggio.", image: "08_leg_curl", folder: imageFolder),
            exercise("T-bar con appoggio al petto", muscle: "Dorso", execution: "Rematore T-bar con il petto sul supporto. Tira le impugnature verso il busto, poi distendi le braccia con controllo mantenendo l’appoggio.", image: "09_tbar", folder: imageFolder),
            exercise("Alzate laterali", muscle: "Spalle", execution: "Solleva i manubri lateralmente con i gomiti leggermente piegati, poi abbassali con controllo senza slanci del busto.", image: "10_alzate_laterali", folder: imageFolder),
            exercise("Calf in piedi", muscle: "Polpacci", execution: "Sollevamento dei talloni in piedi alla macchina. Sali sulle punte e abbassa i talloni lentamente mantenendo un appoggio stabile.", image: "11_calf_in_piedi", folder: imageFolder),
            exercise("Alzate a busto flesso", muscle: "Spalle", execution: "Alzate con manubri a busto flesso. Con il busto stabile, solleva le braccia lateralmente e torna alla posizione iniziale con controllo.", image: "12_alzate_busto_flesso", folder: imageFolder),
            exercise("Crunch", muscle: "Addominali", execution: "Da sdraiato con le ginocchia piegate, solleva le spalle dal pavimento flettendo il busto, poi torna alla posizione iniziale con controllo.", image: "13_crunch", folder: imageFolder),
            exercise("Calf seduto", muscle: "Polpacci", execution: "Sollevamento dei talloni da seduto alla macchina. Sali sulle punte e abbassa i talloni lentamente mantenendo le ginocchia piegate.", image: "14_calf_seduto", folder: imageFolder),
            exercise("Plank", muscle: "Addominali", execution: "Mantieni la posizione in appoggio sugli avambracci e sulle punte dei piedi, con il busto stabile. La durata è scelta da te.", image: "15_plank", folder: imageFolder)
        ]
        data.plans = (try? fourDayPlan(exercises: data.exercises)).map { [$0] } ?? []
        data.foods = [
            food("Fiocchi d’avena", kcal: 367, p: 8, f: 7.5, c: 66.8, code: "003030"),
            food("Banana fresca · parte edibile", kcal: 76, p: 1.2, f: 0.3, c: 17.4, code: "007510"),
            food("Riso brillato · crudo", kcal: 334, p: 6.7, f: 0.4, c: 80.4, code: "000100"),
            food("Petto di pollo · crudo", kcal: 100, p: 23.3, f: 0.8, c: 0, code: "106500"),
            food("Olio extravergine d’oliva", kcal: 899, p: 0, f: 99.9, c: 0, code: "009210"),
            // CREA reports milk per 100 g. Do not silently turn grams into millilitres.
            food("Latte parzialmente scremato · per 100 g", kcal: 46, p: 3.5, f: 1.5, c: 5, code: "135020")
        ]
        data.notes = [DiaryNote(title: "Benvenuto in DailyFit", body: "Questo spazio funziona come un blocco note. Puoi annotare carichi, sensazioni o idee senza modificare le schede.\n\nNel catalogo trovi esercizi e alimenti iniziali modificabili. Imposta le tue schede, il peso e gli obiettivi prima di iniziare. I valori degli alimenti CREA sono riferimenti per 100 g di parte edibile: per prodotti confezionati usa l’etichetta.\n\nTieni premuto il pulsante ChatGPT per collegare una conversazione dedicata.")]
        return data
    }
    static func initialData() throws -> AppData {
        let data = makeData()
        try validateCatalog(data.exercises)
        guard data.plans.count == 1 else { throw InputError.invalid("Scheda iniziale non disponibile.") }
        try data.validate()
        return data
    }

    /// Called only for archives created before automatic defaults were introduced.
    @discardableResult
    static func installDefaultsIfNeeded(to data: inout AppData, catalog: [Exercise]? = nil) throws -> Bool {
        guard (data.defaultContentVersion ?? 0) < contentVersion else { return false }
        var candidate = data
        _ = try addMissingExercises(to: &candidate, catalog: catalog ?? makeData().exercises)
        let plan = try fourDayPlan(exercises: candidate.exercises)
        let alreadyPresent = candidate.plans.contains { existing in
            catalogKey(existing.name) == catalogKey(fourDayPlanName) ||
            (existing.days.map(\.name) == plan.days.map(\.name) &&
             existing.days.map { $0.entries.map(\.exerciseID) } == plan.days.map { $0.entries.map(\.exerciseID) })
        }
        if !alreadyPresent { candidate.plans.append(plan) }
        candidate.defaultContentVersion = contentVersion
        try candidate.validate()
        data = candidate
        return true
    }

    private static func validateCatalog(_ catalog: [Exercise]) throws {
        guard !catalog.isEmpty else { throw InputError.invalid("Il catalogo incluso è vuoto.") }
        for exercise in catalog {
            try exercise.validate()
            guard let photo = exercise.photo, !photo.isEmpty,
                  let muscles = exercise.musclePhoto, !muscles.isEmpty else {
                throw InputError.invalid("Mancano le immagini incluse di \(exercise.name). Trasferisci sul Mac l’intera cartella iOS e apri il progetto aggiornato.")
            }
        }
    }

    static func addMissingExercises(to data: inout AppData, catalog: [Exercise]) throws -> Int {
        try validateCatalog(catalog)
        var names = Set(data.exercises.map { catalogKey($0.name) })
        var additions: [Exercise] = []
        for var exercise in catalog where names.insert(catalogKey(exercise.name)).inserted {
            exercise.id = UUID()
            additions.append(exercise)
        }
        var candidate = data
        candidate.exercises.append(contentsOf: additions)
        try candidate.validate()
        data = candidate
        return additions.count
    }
    static let fourDayPlanName = "Scheda palestra — 4 giorni"

    static func fourDayPlan(exercises: [Exercise]) throws -> TrainingPlan {
        func entry(_ catalogName: String, _ count: Int, _ reps: Int, upper: Int? = nil, seconds: Bool = false, name: String? = nil) throws -> TrainingEntry {
            guard let exercise = exercises.first(where: { catalogKey($0.name) == catalogKey(catalogName) }) else {
                throw InputError.invalid("Manca l’esercizio \(catalogName) necessario alla scheda.")
            }
            return TrainingEntry(exerciseID: exercise.id,
                sets: (0..<count).map { _ in TrainingSet(reps: reps, upperReps: upper, unit: seconds ? .seconds : nil) },
                nameOverride: name)
        }
        return try TrainingPlan(name: fourDayPlanName, days: [
            TrainingDay(name: "Lunedì — Parte alta A", entries: [
                entry("Panca piana con bilanciere", 3, 6, name: "Panca piana bilanciere"),
                entry("Panca inclinata con manubri", 3, 8, name: "Panca inclinata manubri"),
                entry("Trazioni supine", 2, 8, name: "Trazioni supine secondarie"),
                entry("T-bar con appoggio al petto", 3, 8),
                entry("Alzate laterali", 2, 10),
                entry("Alzate a busto flesso", 2, 10)
            ]),
            TrainingDay(name: "Martedì — Parte bassa A", entries: [
                entry("Squat con bilanciere", 3, 6, name: "Squat pesante"),
                entry("Leg extension", 3, 8),
                entry("Stacco sumo", 2, 8, name: "Stacco sumo leggero"),
                entry("Leg curl sdraiato", 3, 8, name: "Leg curl"),
                entry("Calf in piedi", 3, 15),
                entry("Crunch", 2, 12, upper: 20)
            ]),
            TrainingDay(name: "Giovedì — Parte alta B", entries: [
                entry("Trazioni supine", 3, 4, name: "Trazioni supine pesanti"),
                entry("Lat machine stretta supina", 2, 8),
                entry("Panca piana con bilanciere", 3, 8, name: "Panca piana secondaria"),
                entry("Panca inclinata con manubri", 3, 8, name: "Panca inclinata manubri"),
                entry("Alzate laterali", 2, 10),
                entry("Alzate a busto flesso", 2, 10)
            ]),
            TrainingDay(name: "Venerdì — Parte bassa B", entries: [
                entry("Stacco sumo", 3, 4, name: "Stacco sumo pesante"),
                entry("Leg curl sdraiato", 3, 8, name: "Leg curl"),
                entry("Squat con bilanciere", 2, 8, name: "Squat secondario"),
                entry("Leg extension", 3, 8),
                entry("Calf seduto", 3, 15),
                entry("Plank", 2, 20, upper: 40, seconds: true)
            ])
        ])
    }
    private static func catalogKey(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    private static func exercise(_ name: String, muscle: String, execution: String, image: String, folder: URL?) -> Exercise {
        Exercise(name: name, muscle: muscle, execution: execution,
                 photo: picture(image + "_esecuzione", folder: folder),
                 musclePhoto: picture(image + "_muscoli", folder: folder))
    }
    private static func picture(_ name: String, folder: URL?) -> Data? {
        let url = folder?.appendingPathComponent(name + ".jpg") ?? Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "ExerciseImages")
        guard let url, let bytes = try? Data(contentsOf: url), !bytes.isEmpty, bytes.count <= 2_000_000 else { return nil }
        return bytes
    }
    private static func food(_ name: String, kcal: Double, p: Double, f: Double, c: Double, code: String) -> Food {
        Food(name: name, nutrients: Nutrients(kcal: kcal, protein: p, fat: f, carbs: c), source: "CREA Centro di ricerca Alimenti e Nutrizione · Tabelle 2019 · valori per 100 g di parte edibile", sourceURL: "https://www.alimentinutrizione.it/tabelle-nutrizionali/" + code)
    }
}

import Foundation
import Combine
import UIKit
import CryptoKit

/// Private disk format only. Public JSON backups remain self-contained version 1.
struct LocalImageEnvelope: Codable {
    var storageFormat = "DailyFitLocal"
    var storageVersion = 2
    var data: AppData
    var images: [String: [String: String]]
}

struct DeletionUndo {
    let id = UUID()
    let label: String
    let previous: AppData
    let expiresAt: Date
}

/// One writer, incremental SQLite transactions, complete iOS file protection. No cloud container.
actor LocalRepository {
    let folder: URL
    private var latestRevision: UInt64? = nil
    private struct StoredImage { let filename: String; let count: Int }
    private var cleanedAtLaunch = false
    private var imageCache: [String: StoredImage] = [:]
    private var recordCache: [String: LocalRecord] = [:]
    private var recordSizes: [String: Int] = [:]
    private var prepared = false
    private var cacheLoaded = false
    private var validatedSnapshot: AppData?
    private lazy var database = SQLiteRecords(url: folder.appendingPathComponent("records-v3.sqlite"))
    private(set) var lastWrittenKeys = Set<String>()
    private(set) var lastWrittenBytes = 0
    init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DailyFit", isDirectory: true)
    }
    private var file: URL { folder.appendingPathComponent("data-v1.json") }
    private var imageFolder: URL { folder.appendingPathComponent("images-v2", isDirectory: true) }
    private func prepare() throws {
        guard !prepared else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var url = folder
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        prepared = true
    }
    func load(includingImages: Bool = true) throws -> AppData {
        try prepare()
        let records = try database.read()
        if !records.isEmpty {
            let decoder = JSONDecoder()
            let decoded = try records.mapValues { try decoder.decode(LocalRecord.self, from: $0) }
            var data = try restoreImages(RecordArchive.join(decoded), validateMetadata: false)
            try prepareLoadedData(&data)
            recordCache = decoded; recordSizes = records.mapValues(\.count)
            cacheLoaded = true
            validatedSnapshot = data
            if !cleanedAtLaunch && !data.hasLegacyFoodUnits { removeUnusedImages(); cleanedAtLaunch = true }
            return includingImages ? try materialize(data) : data
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            let initial = try SeedCatalog.initialData(); try initial.validate()
            cacheLoaded = true; validatedSnapshot = initial; return initial
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue > 0, size.intValue <= BackupCodec.sizeLimit else { throw InputError.invalid("Dimensione dell’archivio non valida.") }
        let bytes = try Data(contentsOf: file)
        guard bytes.count <= 64_000_000 else { throw InputError.invalid("Archivio troppo grande.") }
        var data: AppData
        if let envelope = try? JSONDecoder().decode(LocalImageEnvelope.self, from: bytes) {
            guard envelope.storageFormat == "DailyFitLocal", envelope.storageVersion == 2 else {
                throw InputError.invalid("Archivio locale non compatibile.")
            }
            data = try restoreImages(envelope, validateMetadata: false)
        } else {
            // The legacy file is left untouched until a validated SQLite save succeeds.
            data = try JSONDecoder().decode(AppData.self, from: bytes)
        }
        try prepareLoadedData(&data)
        cacheLoaded = true
        validatedSnapshot = data
        return includingImages ? try materialize(data) : data
    }
    private func prepareLoadedData(_ data: inout AppData) throws {
        if data.hasLegacyFoodUnits {
            // Open for manual correction; retain units, quantities and all other stored values.
            try data.validate(allowLegacyFoodUnits: true)
        } else {
            data.migrateLegacyGoals()
            try data.validate()
            try SeedCatalog.installDefaultsIfNeeded(to: &data)
            try data.validate()
        }
    }
    @discardableResult
    func save(_ data: AppData, revision: UInt64, allowLegacyFoodUnits: Bool = false) throws -> AppData {
        if let latestRevision, revision <= latestRevision {
            return revision == latestRevision ? (validatedSnapshot ?? data) : data
        }
        try prepare()
        // Also support a repository opened directly for a restore, without a preceding load.
        // Decode the previous archive before replacing it; corruption must never be hidden.
        if !cacheLoaded { _ = try load(includingImages: false) }
        try data.validate(changesFrom: validatedSnapshot, allowLegacyFoodUnits: allowLegacyFoodUnits)
        var metadata = data
        var references: [String: [String: String]] = [:]
        var nextCache: [String: StoredImage] = [:]
        var pictureCharacters = 0
        for i in metadata.exercises.indices {
            let exercise = metadata.exercises[i], id = exercise.id.uuidString
            var fields: [String: String] = [:]
            for (field, picture, reference) in [("photo", exercise.photo, exercise.photoFile), ("musclePhoto", exercise.musclePhoto, exercise.musclePhotoFile)] {
                let stored: StoredImage
                if let picture {
                    let filename = Self.imageDigest(picture) + ".bin"
                    try FileManager.default.createDirectory(at: imageFolder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
                    let url = imageFolder.appendingPathComponent(filename)
                    if !FileManager.default.fileExists(atPath: url.path) {
                        try picture.write(to: url, options: [.atomic, .completeFileProtection])
                    }
                    stored = StoredImage(filename: filename, count: picture.count)
                } else if let reference {
                    stored = StoredImage(filename: reference, count: try imageSize(reference))
                } else { continue }
                nextCache[id + ":" + field] = stored; fields[field] = stored.filename
                pictureCharacters += ((stored.count + 2) / 3) * 4
            }
            if !fields.isEmpty { references[id] = fields }
            metadata.exercises[i].photo = nil; metadata.exercises[i].musclePhoto = nil
            metadata.exercises[i].photoFile = nil; metadata.exercises[i].musclePhotoFile = nil
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let nextRecords = RecordArchive.split(LocalImageEnvelope(data: metadata, images: references))
        var writes: [String: Data] = [:], nextSizes = recordSizes
        let deletes = Set(recordCache.keys).subtracting(nextRecords.keys)
        for (key, value) in nextRecords where recordCache[key] != value {
            let bytes = try encoder.encode(value); writes[key] = bytes; nextSizes[key] = bytes.count
        }
        for key in deletes { nextSizes[key] = nil }
        guard nextSizes.values.reduce(pictureCharacters, +) <= BackupCodec.sizeLimit else { throw InputError.invalid("Archivio troppo grande: riduci le immagini.") }
        try database.apply(writes: writes, deletes: deletes)
        recordCache = nextRecords; recordSizes = nextSizes
        lastWrittenKeys = Set(writes.keys).union(deletes)
        lastWrittenBytes = writes.values.reduce(0) { $0 + $1.count }
        imageCache = nextCache
        latestRevision = revision
        var normalized = metadata
        for i in normalized.exercises.indices {
            let fields = references[normalized.exercises[i].id.uuidString]
            normalized.exercises[i].photoFile = fields?["photo"]
            normalized.exercises[i].musclePhotoFile = fields?["musclePhoto"]
        }
        validatedSnapshot = normalized
        // Migration is committed. A corrupt database must never fall back to stale JSON.
        if FileManager.default.fileExists(atPath: file.path) { try? FileManager.default.removeItem(at: file) }
        // Retain deleted files during this process for Undo, open editors and exports.
        // Unreferenced files are reclaimed at the next cold launch.
        return normalized
    }

    static func imageDigest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    private func restoreImages(_ envelope: LocalImageEnvelope, validateMetadata: Bool = true) throws -> AppData {
        var data = envelope.data
        if validateMetadata { try data.validate() }
        guard data.exercises.allSatisfy({ $0.photo == nil && $0.musclePhoto == nil && $0.photoFile == nil && $0.musclePhotoFile == nil }) else {
            throw InputError.invalid("Metadati immagini locali non validi.")
        }
        var cache: [String: StoredImage] = [:]
        var restoredIDs = Set<UUID>()
        var size = 0
        for (rawID, fields) in envelope.images {
            guard let id = UUID(uuidString: rawID), restoredIDs.insert(id).inserted,
                  let i = data.exercises.firstIndex(where: { $0.id == id }),
                  fields.keys.allSatisfy({ $0 == "photo" || $0 == "musclePhoto" }) else {
                throw InputError.invalid("Riferimento immagine non valido.")
            }
            for (field, filename) in fields {
                guard filename.range(of: #"^[0-9a-f]{64}\.bin$"#, options: .regularExpression) != nil else {
                    throw InputError.invalid("Percorso immagine non valido.")
                }
                let count = try imageSize(filename)
                size += ((count + 2) / 3) * 4
                guard size <= BackupCodec.sizeLimit else { throw InputError.invalid("Immagini dell’archivio troppo grandi.") }
                if field == "photo" { data.exercises[i].photoFile = filename } else { data.exercises[i].musclePhotoFile = filename }
                cache[id.uuidString + ":" + field] = StoredImage(filename: filename, count: count)
            }
        }
        imageCache = cache
        return data
    }
    private func imageSize(_ filename: String) throws -> Int {
        guard filename.range(of: #"^[0-9a-f]{64}\.bin$"#, options: .regularExpression) != nil else {
            throw InputError.invalid("Percorso immagine non valido.")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: imageFolder.appendingPathComponent(filename).path)
        guard let count = attributes[.size] as? NSNumber, count.intValue > 0, count.intValue <= 2_000_000 else {
            throw InputError.invalid("Dimensione immagine locale non valida.")
        }
        return count.intValue
    }

    func imageBytes(_ filename: String) throws -> Data {
        _ = try imageSize(filename)
        let bytes = try Data(contentsOf: imageFolder.appendingPathComponent(filename))
        guard bytes.count <= 2_000_000, Self.imageDigest(bytes) + ".bin" == filename else {
            throw InputError.invalid("Immagine locale danneggiata.")
        }
        return bytes
    }

    func materialize(_ snapshot: AppData) throws -> AppData {
        var result = snapshot
        for i in result.exercises.indices {
            if result.exercises[i].photo == nil, let file = result.exercises[i].photoFile { result.exercises[i].photo = try imageBytes(file) }
            if result.exercises[i].musclePhoto == nil, let file = result.exercises[i].musclePhotoFile { result.exercises[i].musclePhoto = try imageBytes(file) }
            result.exercises[i].photoFile = nil; result.exercises[i].musclePhotoFile = nil
        }
        return result
    }

    private func removeUnusedImages() {
        let used = Set(imageCache.values.map(\.filename))
        guard let urls = try? FileManager.default.contentsOfDirectory(at: imageFolder, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.lastPathComponent.range(of: #"^[0-9a-f]{64}\.bin$"#, options: .regularExpression) != nil && !used.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var data = AppData()
    @Published private(set) var ready = false
    @Published var loadError: String? = nil
    @Published var message: String? = nil
    @Published var editorCount = 0
    private let repository: LocalRepository
    private var revision: UInt64 = 0
    private var loading = false
    private var pendingSave: Task<Void, Never>?
    @Published private(set) var restoring = false
    @Published private(set) var deletionUndo: DeletionUndo? = nil
    private var undoExpiry: Task<Void, Never>?
    init(repository: LocalRepository = LocalRepository()) { self.repository = repository }
    func load() async {
        guard !ready, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let loaded = try await repository.load(includingImages: false)
            data = loaded; ready = true; loadError = nil
            if !loaded.hasLegacyFoodUnits { revision += 1; await flush() }
        } catch { loadError = "I dati non sono stati aperti. Non sono stati sostituiti. Dettaglio: \(error.localizedDescription)" }
    }
    @discardableResult
    func change(_ edit: (inout AppData) throws -> Void) -> Bool {
        guard ready, !restoring else { return false }
        do {
            var candidate = data
            try edit(&candidate)
            guard candidate != data else { return true }
            try candidate.validate(changesFrom: data)
            if deletionUndo != nil {
                var before = data, after = candidate
                before.timer = nil; after.timer = nil
                if before != after { discardDeletionUndo() }
            }
            data = candidate; revision += 1; queueSave()
            return true
        } catch { message = error.localizedDescription; return false }
    }
    @discardableResult
    func delete(label: String, at now: Date = Date(), _ edit: (inout AppData) throws -> Void) -> Bool {
        var previous = data
        previous.timer = nil
        guard change(edit) else { return false }
        var current = data; current.timer = nil
        guard current != previous else { return true }
        discardDeletionUndo()
        let undo = DeletionUndo(label: label, previous: previous, expiresAt: now.addingTimeInterval(15))
        deletionUndo = undo
        undoExpiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            if self?.deletionUndo?.id == undo.id { self?.discardDeletionUndo() }
        }
        return true
    }

    @discardableResult
    func undoLastDeletion(at now: Date = Date()) -> Bool {
        guard ready, !restoring, let undo = deletionUndo else { return false }
        guard now < undo.expiresAt else { discardDeletionUndo(); return false }
        // A countdown may have changed since deletion; never resurrect an old one.
        var previous = undo.previous
        previous.timer = data.timer
        return change { $0 = previous }
    }

    func discardDeletionUndo() {
        undoExpiry?.cancel(); undoExpiry = nil; deletionUndo = nil
    }
    private func queueSave() {
        pendingSave?.cancel()
        let snapshot = data, rev = revision, repository = repository
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)); try Task.checkCancellation(); let saved = try await repository.save(snapshot, revision: rev); if self?.revision == rev { self?.data = saved } }
            catch is CancellationError { }
            catch { self?.message = "Salvataggio non riuscito. I dati restano aperti in memoria: \(error.localizedDescription)" }
        }
    }
    func flush() async {
        guard ready, !restoring, revision > 0 else { return }
        pendingSave?.cancel()
        let snapshot = data, rev = revision
        do { let saved = try await repository.save(snapshot, revision: rev); if revision == rev { data = saved } }
        catch { message = "Salvataggio non riuscito: \(error.localizedDescription)" }
    }
    @discardableResult
    func restoreBackup(_ imported: AppData) async -> Bool {
        guard ready, !restoring else { return false }
        restoring = true
        defer { restoring = false }
        pendingSave?.cancel()
        do {
            var candidate = imported
            candidate.timer = nil
            // An explicit restore must keep exactly the chosen contents on future launches.
            candidate.defaultContentVersion = max(candidate.defaultContentVersion ?? 0, SeedCatalog.contentVersion)
            try candidate.validate(allowLegacyFoodUnits: true)
            let nextRevision = revision + 1
            // Replace the live state only after its atomic write has succeeded.
            let saved = try await repository.save(candidate, revision: nextRevision, allowLegacyFoodUnits: true)
            revision = nextRevision
            discardDeletionUndo()
            data = saved
            return true
        } catch {
            message = "Ripristino non riuscito. I dati attuali restano disponibili: \(error.localizedDescription)"
            queueSave()
            return false
        }
    }
    func imageBytes(_ filename: String) async throws -> Data { try await repository.imageBytes(filename) }
    func exportSnapshot(_ snapshot: AppData) async throws -> AppData { try await repository.materialize(snapshot) }

    func flushForBackground() {
        // A finite save operation, not a background timer or a background capability.
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "Salvataggio locale", expirationHandler: nil)
        Task {
            await flush()
            if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
        }
    }
    @discardableResult
    func saveNote(_ note: DiaryNote) -> Bool {
        if note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !data.notes.contains(where: { $0.id == note.id }) { return true }
        return change { data in
            if let i = data.notes.firstIndex(where: { $0.id == note.id }) { data.notes[i] = note } else { data.notes.append(note) }
        }
    }
}

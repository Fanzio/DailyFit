import Foundation

struct BackupEnvelope: Codable {
    let format: String
    let version: Int
    let exportedAt: Date
    var data: AppData
}

enum BackupCodec {
    static let sizeLimit = 64_000_000

    static func encode(_ data: AppData, at date: Date = Date()) throws -> Data {
        try requireEmbeddedImages(data)
        try data.validate(allowLegacyFoodUnits: true)
        var snapshot = data
        // Recovery restores user data, not an old countdown.
        snapshot.timer = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(BackupEnvelope(format: "DailyFit", version: 1, exportedAt: date, data: snapshot))
        guard bytes.count <= sizeLimit else { throw InputError.invalid("Backup troppo grande.") }
        return bytes
    }

    static func decode(_ bytes: Data) throws -> AppData {
        guard !bytes.isEmpty, bytes.count <= sizeLimit else { throw InputError.invalid("Dimensione del backup non valida.") }
        let envelope = try JSONDecoder().decode(BackupEnvelope.self, from: bytes)
        guard envelope.format == "DailyFit", envelope.version == 1 else {
            throw InputError.invalid("Questo file non è un backup compatibile di DailyFit.")
        }
        var data = envelope.data
        try requireEmbeddedImages(data)
        data.timer = nil
        if !data.hasLegacyFoodUnits { data.migrateLegacyGoals() }
        try data.validate(allowLegacyFoodUnits: true)
        return data
    }

    private static func requireEmbeddedImages(_ data: AppData) throws {
        guard data.exercises.allSatisfy({ $0.photoFile == nil && $0.musclePhotoFile == nil }) else {
            throw InputError.invalid("Il backup deve contenere le immagini, non percorsi locali.")
        }
    }
}

extension LocalRepository {
    static func readBackup(_ url: URL) throws -> AppData {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var readError: Error?
        var result: AppData?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: readable.path)
                guard let size = attributes[.size] as? NSNumber, size.intValue > 0, size.intValue <= BackupCodec.sizeLimit else {
                    throw InputError.invalid("Dimensione del backup non valida.")
                }
                result = try BackupCodec.decode(Data(contentsOf: readable))
            } catch { readError = error }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        guard let result else { throw InputError.invalid("Backup non leggibile.") }
        return result
    }
}

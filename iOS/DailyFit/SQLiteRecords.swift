import Foundation
import SQLite3

/// Confined to LocalRepository's actor. SQLite commits only the affected records.
final class SQLiteRecords {
    let url: URL
    private var connection: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    init(url: URL) { self.url = url }
    deinit { if let connection { sqlite3_close_v2(connection) } }

    private func database() throws -> OpaquePointer {
        if let connection { return connection }
        var handle: OpaquePointer?
        let code = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK, let handle else {
            if let handle { sqlite3_close_v2(handle) }
            throw InputError.invalid("Database locale non apribile. I dati esistenti sono stati conservati.")
        }
        connection = handle
        do {
            sqlite3_busy_timeout(handle, 3000)
            let version = try integer("PRAGMA user_version")
            guard version == 0 || version == 3 else { throw InputError.invalid("Versione del database non supportata.") }
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            if version == 0 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("CREATE TABLE records (key TEXT PRIMARY KEY NOT NULL, value BLOB NOT NULL)")
                    try execute("PRAGMA user_version=3")
                    try execute("COMMIT")
                } catch { try? execute("ROLLBACK"); throw error }
            }
            return handle
        } catch { connection = nil; sqlite3_close_v2(handle); throw error }
    }
    func execute(_ sql: String) throws {
        let db = try database()
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure(db) }
    }
    private func statement(_ sql: String) throws -> OpaquePointer {
        let db = try database(); var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw failure(db)
        }
        return statement
    }
    func integer(_ sql: String) throws -> Int {
        let stmt = try statement(sql); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw failure(try database()) }
        return Int(sqlite3_column_int(stmt, 0))
    }
    private func failure(_ db: OpaquePointer) -> Error {
        InputError.invalid("Operazione sul database non riuscita: " + String(cString: sqlite3_errmsg(db)))
    }
    func read() throws -> [String: Data] {
        let stmt = try statement("SELECT key,value FROM records"); defer { sqlite3_finalize(stmt) }
        var result: [String: Data] = [:], total = 0
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW, let key = sqlite3_column_text(stmt, 0), let bytes = sqlite3_column_blob(stmt, 1) else { throw failure(try database()) }
            let count = Int(sqlite3_column_bytes(stmt, 1)); total += count
            guard count > 0, total <= BackupCodec.sizeLimit, result.count < 200_000 else { throw InputError.invalid("Database troppo grande o non valido.") }
            result[String(cString: key)] = Data(bytes: bytes, count: count)
        }
        return result
    }
    func apply(writes: [String: Data], deletes: Set<String>) throws {
        guard !writes.isEmpty || !deletes.isEmpty else { return }
        let db = try database()
        try execute("BEGIN IMMEDIATE")
        do {
            let put = try statement("INSERT OR REPLACE INTO records(key,value) VALUES(?,?)")
            defer { sqlite3_finalize(put) }
            let remove = try statement("DELETE FROM records WHERE key=?")
            defer { sqlite3_finalize(remove) }
            for (key, bytes) in writes {
                guard key.withCString({ sqlite3_bind_text(put, 1, $0, -1, transient) }) == SQLITE_OK,
                      bytes.withUnsafeBytes({ sqlite3_bind_blob(put, 2, $0.baseAddress, Int32(bytes.count), transient) }) == SQLITE_OK,
                      sqlite3_step(put) == SQLITE_DONE else { throw failure(db) }
                sqlite3_reset(put); sqlite3_clear_bindings(put)
            }
            for key in deletes {
                guard key.withCString({ sqlite3_bind_text(remove, 1, $0, -1, transient) }) == SQLITE_OK,
                      sqlite3_step(remove) == SQLITE_DONE else { throw failure(db) }
                sqlite3_reset(remove); sqlite3_clear_bindings(remove)
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
}

enum LocalRecord: Codable, Equatable {
    case settings(AppData), order([UUID]), exercise(Exercise, [String: String])
    case plan(TrainingPlan), day(TrainingDay), note(DiaryNote), food(Food), diet(DietDay)
}

enum RecordArchive {
    static func split(_ envelope: LocalImageEnvelope) -> [String: LocalRecord] {
        let data = envelope.data
        var settings = data
        settings.exercises = []; settings.plans = []; settings.notes = []; settings.foods = []
        settings.week = []; settings.dates = [:]
        var rows: [String: LocalRecord] = ["settings": .settings(settings)]
        rows["order/exercises"] = .order(data.exercises.map(\.id))
        rows["order/foods"] = .order(data.foods.map(\.id))
        rows["order/notes"] = .order(data.notes.map(\.id))
        rows["order/plans"] = .order(data.plans.map(\.id))
        for e in data.exercises { rows["exercises/" + e.id.uuidString] = .exercise(e, envelope.images[e.id.uuidString] ?? [:]) }
        for f in data.foods { rows["foods/" + f.id.uuidString] = .food(f) }
        for n in data.notes { rows["notes/" + n.id.uuidString] = .note(n) }
        for plan in data.plans {
            var header = plan; header.days = []
            let prefix = "plans/" + plan.id.uuidString
            rows[prefix] = .plan(header); rows[prefix + "/order"] = .order(plan.days.map(\.id))
            for day in plan.days { rows[prefix + "/day/" + day.id.uuidString] = .day(day) }
        }
        for (i, day) in data.week.enumerated() { rows["week/\(i)"] = .diet(day) }
        for (date, day) in data.dates { rows["date/" + date] = .diet(day) }
        return rows
    }
    static func join(_ rows: [String: LocalRecord]) throws -> LocalImageEnvelope {
        var used = Set<String>()
        let invalid = InputError.invalid("Database incompleto o riferimenti non validi.")
        func take(_ key: String) throws -> LocalRecord {
            guard let row = rows[key], used.insert(key).inserted else { throw invalid }; return row
        }
        func order(_ key: String) throws -> [UUID] {
            guard case let .order(ids) = try take(key) else { throw invalid }; return ids
        }
        guard case var .settings(data) = try take("settings") else { throw invalid }
        guard data.exercises.isEmpty, data.foods.isEmpty, data.notes.isEmpty, data.plans.isEmpty,
              data.week.isEmpty, data.dates.isEmpty else { throw invalid }
        var images: [String: [String: String]] = [:]
        for id in try order("order/exercises") {
            guard case let .exercise(e, refs) = try take("exercises/" + id.uuidString), e.id == id else { throw invalid }
            data.exercises.append(e); images[id.uuidString] = refs
        }
        for id in try order("order/foods") {
            guard case let .food(f) = try take("foods/" + id.uuidString), f.id == id else { throw invalid }; data.foods.append(f)
        }
        for id in try order("order/notes") {
            guard case let .note(n) = try take("notes/" + id.uuidString), n.id == id else { throw invalid }; data.notes.append(n)
        }
        for id in try order("order/plans") {
            let prefix = "plans/" + id.uuidString
            guard case var .plan(plan) = try take(prefix), plan.id == id else { throw invalid }
            guard plan.days.isEmpty else { throw invalid }
            for dayID in try order(prefix + "/order") {
                guard case let .day(day) = try take(prefix + "/day/" + dayID.uuidString), day.id == dayID else { throw invalid }; plan.days.append(day)
            }
            data.plans.append(plan)
        }
        for i in 0..<7 {
            guard case let .diet(day) = try take("week/\(i)") else { throw invalid }; data.week.append(day)
        }
        for key in rows.keys where key.hasPrefix("date/") {
            guard case let .diet(day) = try take(key) else { throw invalid }; data.dates[String(key.dropFirst(5))] = day
        }
        guard used.count == rows.count else { throw invalid }
        return LocalImageEnvelope(data: data, images: images)
    }
}

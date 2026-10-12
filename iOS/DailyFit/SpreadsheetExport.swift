import Foundation

enum SpreadsheetCell: Equatable {
    case text(String)
    case number(Double)
    case date(Date)
    case blank
    static func optional(_ value: Double?) -> Self { value.map(Self.number) ?? .blank }
}

struct SpreadsheetSheet {
    let name: String
    let headers: [String]
    let rows: [[SpreadsheetCell]]
}

enum SpreadsheetExport {
    static func sheets(for data: AppData) throws -> [SpreadsheetSheet] {
        try data.validate(allowLegacyFoodUnits: true)
        let target = try data.baseGoals.targets(weight: data.bodyWeight)
        let summary = SpreadsheetSheet(name: "Riepilogo", headers: ["Contenuto", "Quantità / indicazione"], rows: [
            [.text("Schede"), .number(Double(data.plans.count))],
            [.text("Giornate palestra"), .number(Double(data.plans.flatMap(\.days).count))],
            [.text("Esercizi, inclusi archiviati"), .number(Double(data.exercises.count))],
            [.text("Note diario"), .number(Double(data.notes.count))],
            [.text("Alimenti, inclusi archiviati"), .number(Double(data.foods.count))],
            [.text("Date con pasti personalizzati"), .number(Double(data.dates.count))],
            [.text("Valori esportati"), .text("Fotografia dei dati al momento dell’esportazione; le modifiche al foglio non aggiornano l’app.")],
            [.text("Ripristino nell’app"), .text("Usa il backup JSON, che conserva anche le immagini. Il file Excel serve per consultare i dati in Google Fogli.")],
            [.text("Note lunghe"), .text("Sono divise in parti consecutive, senza tagliare il testo.")]
        ])
        let goals = SpreadsheetSheet(name: "Obiettivi base", headers: ["Peso (kg)", "Kcal/giorno", "Proteine (g/kg)", "Grassi (g/kg)", "Carboidrati (g/kg)", "Proteine (g/giorno)", "Grassi (g/giorno)", "Carboidrati (g/giorno)"], rows: [[
            .optional(data.bodyWeight), .optional(target.kcal), .optional(data.baseGoals.proteinPerKg), .optional(data.baseGoals.fatPerKg), .optional(data.baseGoals.carbsPerKg), .optional(target.protein), .optional(target.fat), .optional(target.carbs)
        ]])
        let plans = SpreadsheetSheet(name: "Schede", headers: ["ID scheda", "Ordine", "Scheda", "Giornate"], rows: data.plans.enumerated().map { index, plan in
            [.text(plan.id.uuidString), .number(Double(index + 1)), .text(plan.name), .number(Double(plan.days.count))]
        })
        var days: [[SpreadsheetCell]] = []
        var sets: [[SpreadsheetCell]] = []
        for plan in data.plans {
            for (d, day) in plan.days.enumerated() {
                days.append([.text(plan.id.uuidString), .text(plan.name), .text(day.id.uuidString), .number(Double(d + 1)), .text(day.name), .number(Double(day.entries.count))])
                for (e, entry) in day.entries.enumerated() {
                    for (s, set) in entry.sets.enumerated() {
                        let exerciseName = data.exercise(entry.exerciseID).map { entry.displayName(for: $0) } ?? ""
                        sets.append([.text(plan.name), .text(day.name), .number(Double(e + 1)), .text(entry.exerciseID.uuidString), .text(exerciseName), .number(Double(s + 1)), .number(Double(set.reps)), .number(set.load), .number(Double(entry.rest)), .text(plan.id.uuidString), .text(day.id.uuidString), .text(entry.id.uuidString), .text(set.id.uuidString), .optional(set.upperReps.map { Double($0) }), .text(set.effectiveUnit == .seconds ? "Secondi" : "Ripetizioni")])
                    }
                }
            }
        }
        var exercises: [[SpreadsheetCell]] = []
        for exercise in data.exercises {
            for (index, text) in chunks(exercise.execution).enumerated() {
                exercises.append([.text(exercise.id.uuidString), .text(exercise.name), .text(exercise.muscle), .number(Double(index + 1)), .text(text), .text(exercise.video), .text(exercise.photo == nil && exercise.photoFile == nil ? "No" : "Sì · nel backup JSON"), .text(exercise.hasMusclePhoto ? "Sì · nel backup JSON" : "No"), .text(exercise.archived ? "Sì" : "No")])
            }
        }
        var notes: [[SpreadsheetCell]] = []
        for note in data.notes.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            for (index, text) in chunks(note.body).enumerated() {
                notes.append([.text(note.id.uuidString), .text(note.title), .date(note.updatedAt), .number(Double(index + 1)), .text(text)])
            }
        }
        let foods = SpreadsheetSheet(name: "Alimenti", headers: ["ID alimento", "Alimento", "Unità per 100", "Kcal", "Proteine (g)", "Grassi (g)", "Carboidrati (g)", "Fonte", "Link fonte", "Archiviato"], rows: data.foods.map { food in
            [.text(food.id.uuidString), .text(food.name), .text(food.unit.rawValue), .number(food.nutrients.kcal), .number(food.nutrients.protein), .number(food.nutrients.fat), .number(food.nutrients.carbs), .text(food.source), .text(food.sourceURL), .text(food.archived ? "Sì" : "No")]
        })
        var diet: [[SpreadsheetCell]] = []
        var totals: [[SpreadsheetCell]] = []
        func addDiet(_ day: DietDay, kind: String, label: String, date: Date?) {
            let nutrients = data.totals(day)
            totals.append([.text(kind), .text(label), date.map(SpreadsheetCell.date) ?? .blank, .number(nutrients.kcal), .number(nutrients.protein), .number(nutrients.fat), .number(nutrients.carbs)])
            for (m, meal) in day.meals.enumerated() {
                if meal.items.isEmpty {
                    diet.append([.text(kind), .text(label), date.map(SpreadsheetCell.date) ?? .blank, .number(Double(m + 1)), .text(meal.name), .text(meal.isSnack ? "Sì" : "No"), .blank, .blank, .blank, .blank, .blank, .blank, .blank, .blank, .blank, .blank, .text(meal.id.uuidString), .blank])
                }
                for item in meal.items {
                    guard let food = data.food(item) else { continue }
                    let n = food.nutrients.scaled(item.quantity / 100)
                    diet.append([.text(kind), .text(label), date.map(SpreadsheetCell.date) ?? .blank, .number(Double(m + 1)), .text(meal.name), .text(meal.isSnack ? "Sì" : "No"), .text(food.id.uuidString), .text(food.name), .number(item.quantity), .text(food.unit.rawValue), .number(n.kcal), .number(n.protein), .number(n.fat), .number(n.carbs), .text(food.source), .text(food.sourceURL), .text(meal.id.uuidString), .text(item.id.uuidString)])
                }
            }
        }
        for (index, day) in data.week.enumerated() { addDiet(day, kind: "Base", label: Dates.names[index], date: nil) }
        for key in data.dates.keys.sorted() { if let day = data.dates[key] { addDiet(day, kind: "Personalizzata", label: key, date: calendarDate(key)) } }
        return [summary, goals, plans,
            SpreadsheetSheet(name: "Giornate palestra", headers: ["ID scheda", "Scheda", "ID giornata", "Ordine", "Giornata", "Esercizi"], rows: days),
            SpreadsheetSheet(name: "Serie", headers: ["Scheda", "Giornata", "Ordine esercizio", "ID esercizio", "Esercizio", "Serie", "Valore minimo", "Carico (kg)", "Recupero (secondi)", "ID scheda", "ID giornata", "ID inserimento", "ID serie", "Valore massimo", "Unità"], rows: sets),
            SpreadsheetSheet(name: "Esercizi", headers: ["ID esercizio", "Nome", "Gruppo muscolare", "Parte descrizione", "Esecuzione", "Link video", "Immagine", "Immagine muscoli", "Archiviato"], rows: exercises),
            SpreadsheetSheet(name: "Diario", headers: ["ID nota", "Titolo", "Ultima modifica (UTC)", "Parte", "Testo"], rows: notes), foods,
            SpreadsheetSheet(name: "Dieta", headers: ["Tipo", "Giorno", "Data", "Ordine pasto", "Pasto", "Spuntino", "ID alimento", "Alimento", "Quantità", "Unità", "Kcal porzione", "Proteine (g)", "Grassi (g)", "Carboidrati (g)", "Fonte", "Link fonte", "ID pasto", "ID porzione"], rows: diet),
            SpreadsheetSheet(name: "Totali dieta", headers: ["Tipo", "Giorno", "Data", "Kcal", "Proteine (g)", "Grassi (g)", "Carboidrati (g)"], rows: totals),
            SpreadsheetSheet(name: "Impostazioni", headers: ["Impostazione", "Valore"], rows: [[.text("ChatGPT"), .text(data.chatLink)], [.text("Schermo acceso durante allenamento"), .text(data.keepScreenAwake == true ? "Sì" : "No")]])
        ]
    }

    // Excel stores civil dates without a time zone; don't shift the day in UTC.
    static func calendarDate(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    // UTF-16 limits of Excel are respected without splitting surrogate pairs.
    static func chunks(_ text: String, limit: Int = 1000) -> [String] {
        var parts: [String] = [], current = "", count = 0
        for scalar in text.unicodeScalars {
            let width = scalar.value > 0xFFFF ? 2 : 1
            if count + width > limit && !current.isEmpty { parts.append(current); current = ""; count = 0 }
            current.unicodeScalars.append(scalar); count += width
        }
        parts.append(current)
        return parts
    }

    static func encode(_ data: AppData) throws -> Data { try ExcelWorkbook.encode(sheets: sheets(for: data)) }
}

enum ExcelWorkbook {
    private static let ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    private static let relNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private static let declaration = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"

    static func encode(sheets: [SpreadsheetSheet]) throws -> Data {
        guard !sheets.isEmpty, sheets.count < 100, Set(sheets.map(\.name)).count == sheets.count else { throw InputError.invalid("Numero o nomi dei fogli non validi.") }
        var entries: [(String, Data)] = []
        var types = "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        var workbook = "<workbook xmlns=\"\(ns)\" xmlns:r=\"\(relNS)\"><sheets>"
        var relations = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for (index, sheet) in sheets.enumerated() {
            let id = index + 1
            guard sheet.name.count <= 31, !sheet.name.isEmpty,
                  sheet.name.rangeOfCharacter(from: CharacterSet(charactersIn: "[]:*?/\\")) == nil,
                  sheet.rows.count < 1_048_576, sheet.headers.count <= 16_384,
                  sheet.rows.allSatisfy({ $0.count == sheet.headers.count }) else { throw InputError.invalid("Foglio non valido: \(sheet.name).") }
            workbook += "<sheet name=\"\(xml(sheet.name))\" sheetId=\"\(id)\" r:id=\"rId\(id)\"/>"
            relations += "<Relationship Id=\"rId\(id)\" Type=\"\(relNS)/worksheet\" Target=\"worksheets/sheet\(id).xml\"/>"
            types += "<Override PartName=\"/xl/worksheets/sheet\(id).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
            entries.append(("xl/worksheets/sheet\(id).xml", try worksheet(sheet)))
        }
        workbook += "</sheets></workbook>"
        relations += "<Relationship Id=\"styles\" Type=\"\(relNS)/styles\" Target=\"styles.xml\"/></Relationships>"
        types += "</Types>"
        entries.append(("[Content_Types].xml", Data((declaration + types).utf8)))
        entries.append(("_rels/.rels", Data((declaration + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"office\" Type=\"\(relNS)/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>").utf8)))
        entries.append(("xl/workbook.xml", Data((declaration + workbook).utf8)))
        entries.append(("xl/_rels/workbook.xml.rels", Data((declaration + relations).utf8)))
        entries.append(("xl/styles.xml", Data((declaration + styles).utf8)))
        return try ZIPStore.encode(entries)
    }

    static func column(_ index: Int) -> String {
        var value = index + 1, result = ""
        repeat { value -= 1; result = String(UnicodeScalar(65 + value % 26)!) + result; value /= 26 } while value > 0
        return result
    }

    static func xml(_ value: String) -> String {
        let valid = value.unicodeScalars.filter { scalar in
            let v = scalar.value
            return v == 9 || v == 10 || v == 13 || (v >= 0x20 && v <= 0xD7FF) || (v >= 0xE000 && v <= 0xFFFD) || v >= 0x10000
        }
        return String(String.UnicodeScalarView(valid)).replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func worksheet(_ sheet: SpreadsheetSheet) throws -> Data {
        let all = [sheet.headers.map(SpreadsheetCell.text)] + sheet.rows
        let last = "\(column(max(0, sheet.headers.count - 1)))\(all.count)"
        var result = declaration + "<worksheet xmlns=\"\(ns)\"><dimension ref=\"A1:\(last)\"/><sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight=\"20\"/><cols>"
        for (i, header) in sheet.headers.enumerated() {
            let long = ["Testo", "Esecuzione", "Quantità / indicazione"].contains(header)
            result += "<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(long ? 90 : header.hasPrefix("ID") ? 38 : 24)\" customWidth=\"1\"/>"
        }
        result += "</cols><sheetData>"
        for (r, row) in all.enumerated() {
            var lines = 1
            for (i, cell) in row.enumerated() {
                if case .text(let text) = cell {
                    let wide = ["Testo", "Esecuzione", "Quantità / indicazione"].contains(sheet.headers[i])
                    lines = max(lines, text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / (wide ? 70 : 20)))) })
                }
            }
            result += "<row r=\"\(r + 1)\" ht=\"\(min(400, max(r == 0 ? 32 : 22, lines * 16 + 6)))\" customHeight=\"1\">"
            for (c, cell) in row.enumerated() {
                let reference = "\(column(c))\(r + 1)"
                switch cell {
                case .blank: break
                case .text(let text):
                    guard text.utf16.count <= 32767 else { throw InputError.invalid("Testo troppo lungo per una cella Excel.") }
                    // Always inline strings: user text beginning '=' never becomes a formula.
                    result += "<c r=\"\(reference)\" s=\"\(r == 0 ? 1 : 0)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xml(text))</t></is></c>"
                case .number(let number):
                    guard number.isFinite else { throw InputError.invalid("Numero non valido nell’esportazione.") }
                    result += "<c r=\"\(reference)\" s=\"2\"><v>\(number)</v></c>"
                case .date(let date):
                    let serial = date.timeIntervalSince1970 / 86400 + 25569
                    guard serial.isFinite else { throw InputError.invalid("Data non valida nell’esportazione.") }
                    result += "<c r=\"\(reference)\" s=\"3\"><v>\(serial)</v></c>"
                }
            }
            result += "</row>"
        }
        result += "</sheetData><autoFilter ref=\"A1:\(last)\"/></worksheet>"
        return Data(result.utf8)
    }

    private static let styles = """
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <numFmts count="2"><numFmt numFmtId="164" formatCode="#,##0.0"/><numFmt numFmtId="165" formatCode="dd/mm/yyyy hh:mm"/></numFmts>
    <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FF101410"/><name val="Calibri"/></font></fonts>
    <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFC2F36B"/><bgColor indexed="64"/></patternFill></fill></fills>
    <borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment vertical="top"/></xf><xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment vertical="top"/></xf></cellXfs>
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
    """
}

// A small, uncompressed ZIP writer for OOXML; no archive extraction or external SDK.
enum ZIPStore {
    private static let crcTable: [UInt32] = (0..<256).map { value in
        var c = UInt32(value)
        for _ in 0..<8 { c = (c >> 1) ^ ((c & 1) == 1 ? 0xEDB88320 : 0) }
        return c
    }
    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in data { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
    static func encode(_ entries: [(String, Data)]) throws -> Data {
        guard entries.count <= 65535, Set(entries.map { $0.0 }).count == entries.count else { throw InputError.invalid("Archivio Excel non valido.") }
        var bytes = Data(), central = Data()
        for (name, content) in entries {
            let filename = Data(name.utf8)
            guard filename.count <= 65535, content.count <= 100_000_000, bytes.count + content.count <= 100_000_000 else { throw InputError.invalid("Esportazione troppo grande.") }
            let offset = UInt32(bytes.count), length = UInt32(content.count), crc = crc32(content)
            bytes.appendLE(UInt32(0x04034B50)); bytes.appendLE(UInt16(20)); bytes.appendLE(UInt16(0x800)); bytes.appendLE(UInt16(0))
            bytes.appendLE(UInt16(0)); bytes.appendLE(UInt16(33)); bytes.appendLE(crc); bytes.appendLE(length); bytes.appendLE(length)
            bytes.appendLE(UInt16(filename.count)); bytes.appendLE(UInt16(0)); bytes.append(filename); bytes.append(content)
            central.appendLE(UInt32(0x02014B50)); central.appendLE(UInt16(20)); central.appendLE(UInt16(20)); central.appendLE(UInt16(0x800)); central.appendLE(UInt16(0))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(33)); central.appendLE(crc); central.appendLE(length); central.appendLE(length)
            central.appendLE(UInt16(filename.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt32(0)); central.appendLE(offset); central.append(filename)
        }
        let start = UInt32(bytes.count)
        bytes.append(central)
        bytes.appendLE(UInt32(0x06054B50)); bytes.appendLE(UInt16(0)); bytes.appendLE(UInt16(0)); bytes.appendLE(UInt16(entries.count)); bytes.appendLE(UInt16(entries.count)); bytes.appendLE(UInt32(central.count)); bytes.appendLE(start); bytes.appendLE(UInt16(0))
        return bytes
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        for shift in stride(from: 0, to: T.bitWidth, by: 8) { append(UInt8(truncatingIfNeeded: value >> shift)) }
    }
}

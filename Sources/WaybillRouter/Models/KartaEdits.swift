import Foundation

/// Wiersz karty drogowej gotowy do wydruku (już z ręcznymi poprawkami).
struct KartaRow: Hashable {
    var date: Date
    var description: String
    var km: Double
    var edited = false
}

/// Ręczna poprawka jednego wiersza karty. `nil` = bez zmian względem kursu.
struct KartaRowEdit: Codable, Hashable {
    var date: Date?
    var description: String?
    var km: Double?

    var isEmpty: Bool { date == nil && description == nil && km == nil }
}

/// Ręczne poprawki kart drogowych jednego miesiąca.
/// Nie zmieniają kursów, tylko to, co trafia do PDF / Word / CSV.
/// Zapis: Documents/karty/RRRR-MM.json.
struct KartaEdits: Codable, Hashable {
    var carrier: String?
    var car: String?
    var registration: String?
    /// Klucz: `KartaEdits.key(for: trip)`.
    var rows: [String: KartaRowEdit] = [:]

    var isEmpty: Bool { carrier == nil && car == nil && registration == nil && rows.isEmpty }

    static func key(for trip: Trip) -> String {
        String(format: "%.3f", trip.created.timeIntervalSinceReferenceDate)
    }

    /// Poprawka kursu. Gdy klucz nie pasuje co do znaku (zaokrąglenie czasu przy zapisie bazy),
    /// szukamy klucza różniącego się o mniej niż 0,01 s.
    func edit(for trip: Trip) -> KartaRowEdit? {
        let key = Self.key(for: trip)
        if let e = rows[key] { return e }
        let t = trip.created.timeIntervalSinceReferenceDate
        return rows.first { k, _ in Double(k).map { abs($0 - t) < 0.01 } ?? false }?.value
    }

    func row(for trip: Trip) -> KartaRow {
        let e = edit(for: trip)
        return KartaRow(
            date: e?.date ?? trip.date,
            description: e?.description ?? trip.routeDescription,
            km: e?.km ?? trip.km,
            edited: !(e?.isEmpty ?? true)
        )
    }

    func rows(for trips: [Trip]) -> [KartaRow] { trips.map(row(for:)) }

    func header(defaults: KartaHeader) -> KartaHeader {
        KartaHeader(
            carrier: carrier ?? defaults.carrier,
            car: car ?? defaults.car,
            registration: registration ?? defaults.registration
        )
    }

    mutating func set(_ edit: KartaRowEdit, for trip: Trip) {
        let key = Self.key(for: trip)
        // Usuń ewentualny stary, prawie identyczny klucz tego samego kursu.
        let t = trip.created.timeIntervalSinceReferenceDate
        for k in rows.keys where k != key && (Double(k).map { abs($0 - t) < 0.01 } ?? false) {
            rows[k] = nil
        }
        if edit.isEmpty { rows[key] = nil } else { rows[key] = edit }
    }

    // MARK: - Zapis

    private static func url(for month: Date) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("karty", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(KartaExport.fileMonth(month)).json")
    }

    static func load(month: Date) -> KartaEdits {
        guard let data = try? Data(contentsOf: url(for: month)),
              let edits = try? JSONDecoder().decode(KartaEdits.self, from: data) else { return KartaEdits() }
        return edits
    }

    func save(month: Date) {
        let url = Self.url(for: month)
        do {
            if isEmpty {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            } else {
                try JSONEncoder().encode(self).write(to: url, options: .atomic)
            }
            AppLog.log("Zapisano poprawki kart \(KartaExport.fileMonth(month)): \(rows.count) wierszy")
        } catch {
            AppLog.log("Błąd zapisu poprawek kart: \(error.localizedDescription)")
        }
    }
}

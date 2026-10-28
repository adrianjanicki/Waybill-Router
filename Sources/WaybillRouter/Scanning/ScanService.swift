import UIKit
import Vision

/// Wynik odczytu listu przewozowego.
struct ScanResult {
    /// Nazwy firm z kolumny „Trasa” (w kolejności wierszy). Puste, gdy nie znaleziono tabeli.
    var routeFirms: [String]
    /// Pozostały tekst (od góry do dołu), do ręcznego wyboru firm, gdy kolumny nie udało się odczytać.
    var lines: [String]
    /// Data z dokumentu (pierwsza znaleziona dd.mm.rrrr).
    var date: Date?
}

/// Fragment tekstu z OCR z położeniem (współrzędne Vision: 0…1, y rośnie do góry).
struct TextBox {
    var text: String
    var box: CGRect
}

/// OCR (Vision) + wyciąganie firm i daty z listu przewozowego.
enum ScanService {
    /// Słowa z nagłówków dokumentu, które nie są nazwami firm.
    private static let ignoredWords: Set<String> = [
        "lp", "l.p.", "trasa", "nr dok", "dostawy", "data", "podpis", "kierowca", "list przewozowy",
        "sun chemical", "magazyn", "suma", "ilosc", "ilość", "uwagi", "strona",
    ]

    static func recognize(images: [UIImage], knownFirmNames: [String]) async throws -> ScanResult {
        var allLines: [String] = []
        var routeFirms: [String] = []
        for (i, image) in images.enumerated() {
            let boxes = try await recognizeBoxes(in: image)
            AppLog.log("Skan: strona \(i + 1), fragmentów tekstu: \(boxes.count)")
            allLines += boxes.map(\.text)
            if let column = routeColumn(in: boxes), !column.isEmpty {
                AppLog.log("Skan: kolumna „Trasa”: \(column.joined(separator: " | "))")
                routeFirms += column
            } else {
                // Bez nagłówka: wiersze tabeli zaczynają się od numeru L.p. („1 KOSSACKI”).
                let numbered = numberedRows(in: boxes.map(\.text))
                AppLog.log("Skan: brak kolumny „Trasa”, wiersze z numerem: \(numbered.isEmpty ? "brak" : numbered.joined(separator: " | "))")
                routeFirms += numbered
            }
        }
        let date = findDate(in: allLines)
        let firms = unique(routeFirms.map { knownName(for: $0, among: knownFirmNames) ?? Firm.normalized($0) })
        let lines = firms.isEmpty ? unique(allLines.filter(isCandidate)) : []
        AppLog.log("Skan: data \(date.map(Fmt.full) ?? "brak"), firmy: \(firms.joined(separator: ", "))")
        return ScanResult(routeFirms: firms, lines: lines, date: date)
    }

    private static func recognizeBoxes(in image: UIImage) async throws -> [TextBox] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = image.cgOrientation
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            let languages = ["pl-PL", "en-US"].filter { supported.contains($0) }
            if !languages.isEmpty { request.recognitionLanguages = languages }
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try handler.perform([request])
            let observations = request.results ?? []
            // Vision: y rośnie do góry, więc sortujemy malejąco po y, potem po x.
            let sorted = observations.sorted {
                let dy = $0.boundingBox.midY - $1.boundingBox.midY
                if abs(dy) > 0.01 { return dy > 0 }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            return sorted.compactMap { o in
                o.topCandidates(1).first.map { TextBox(text: $0.string, box: o.boundingBox) }
            }
        }.value
    }

    /// Nazwy firm z kolumny „Trasa”: tekst pod nagłówkiem „Trasa”, na lewo od „Nr dok. Dostawy”,
    /// powyżej stopki „Kontenery do zwrotu”. Numery L.p. z początku są obcinane.
    static func routeColumn(in boxes: [TextBox]) -> [String]? {
        let keyed = boxes.map { (Firm.key(for: $0.text), $0) }
        guard let header = keyed.first(where: { $0.0 == "trasa" || $0.0.hasSuffix("_trasa") })?.1 else {
            return nil
        }
        let docHeader = keyed.first(where: { $0.0.contains("nr_dok") || $0.0.hasPrefix("dok_dostawy") })?.1
        // Prawa granica kolumny: początek nagłówka „Nr dok.” (albo rozsądna szerokość, gdy go nie ma).
        let rightEdge = docHeader.map { $0.box.minX } ?? header.box.minX + 0.3
        // Lewa granica: trochę na lewo od „Trasa”, żeby złapać numer L.p. sklejony z nazwą.
        let leftEdge = header.box.minX - 0.08
        // Dół tabeli: pierwsza stopka pod nagłówkiem.
        let footerY = keyed
            .filter { $0.0.contains("kontener") && $0.1.box.midY < header.box.minY }
            .map { $0.1.box.maxY }
            .max() ?? 0

        var names: [String] = []
        for b in boxes {
            let mid = b.box.midY
            guard mid < header.box.minY, mid > footerY,
                  b.box.minX >= leftEdge, b.box.minX < rightEdge - 0.01 else { continue }
            let name = stripRowNumber(b.text)
            guard name.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }),
                  !ignoredWords.contains(name.lowercased()) else { continue }
            names.append(name)
        }
        return names
    }

    /// Linie w stylu „3 HILLWOOD” / „6. SEALED AIR” jako nazwy firm (bez numeru).
    static func numberedRows(in lines: [String]) -> [String] {
        lines.compactMap { line in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.firstMatch(of: #/^\d{1,2}[.)|]?\s+\S/#) != nil else { return nil }
            let name = stripRowNumber(t)
            let letters = name.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            guard letters >= 2, !name.contains(":"), !ignoredWords.contains(name.lowercased()) else { return nil }
            return name
        }
    }

    /// "1 KOSSACKI" → "KOSSACKI", "6. SEALED AIR" → "SEALED AIR", "ASG 47841007," → "ASG".
    static func stripRowNumber(_ s: String) -> String {
        // Numer L.p. tylko z odstępem po nim, żeby nie psuć nazw typu „3M”.
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing(#/^\d{1,2}\s*[.)|]?\s+/#, with: "")
        // Numer dokumentu sklejony z nazwą przez OCR: obcinamy końcowe słowa bez liter.
        var words = t.split(separator: " ")
        while let last = words.last, !last.contains(where: \.isLetter) { words.removeLast() }
        return words.joined(separator: " ")
    }

    /// Jeśli odczytana nazwa to znana firma, zwraca jej zapisaną nazwę.
    static func knownName(for text: String, among firmNames: [String]) -> String? {
        let key = Firm.key(for: text)
        if let exact = firmNames.first(where: { Firm.key(for: $0) == key }) { return exact }
        let padded = "_" + key + "_"
        return firmNames.first { name in
            let k = Firm.key(for: name)
            return k.count > 2 && padded.contains("_" + k + "_")
        }
    }

    static func findDate(in lines: [String]) -> Date? {
        let regex = #/(\d{1,2})[.\-/](\d{1,2})[.\-/](20\d{2})/#
        for line in lines {
            if let m = line.firstMatch(of: regex),
               let d = Int(m.1), let mo = Int(m.2), let y = Int(m.3),
               let date = Calendar.current.date(from: DateComponents(year: y, month: mo, day: d)) {
                return date
            }
        }
        return nil
    }

    private static func isCandidate(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2, t.count <= 40 else { return false }
        let letters = t.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters * 2 >= t.count else { return false }
        return !ignoredWords.contains(t.lowercased())
    }

    private static func unique(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        return lines.filter { seen.insert(Firm.key(for: $0)).inserted }
    }
}

extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}

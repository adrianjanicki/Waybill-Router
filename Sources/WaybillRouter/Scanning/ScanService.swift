import UIKit
import Vision

/// Wynik odczytu listu przewozowego.
struct ScanResult {
    /// Wszystkie linie tekstu (od góry do dołu), do ręcznego wyboru firm.
    var lines: [String]
    /// Firmy, które już znamy i które występują na dokumencie (w kolejności z dokumentu).
    var knownFirms: [String]
    /// Data z dokumentu (pierwsza znaleziona dd.mm.rrrr).
    var date: Date?
}

/// OCR (Vision) + wyciąganie firm i daty z listu przewozowego.
enum ScanService {
    /// Słowa z nagłówków dokumentu, które nie są nazwami firm.
    private static let ignoredWords: Set<String> = [
        "lp", "l.p.", "trasa", "nr dok", "dostawy", "data", "podpis", "kierowca", "list przewozowy",
        "sun chemical", "magazyn", "suma", "ilosc", "ilość", "uwagi", "strona",
    ]

    static func recognize(images: [UIImage], knownFirmNames: [String]) async throws -> ScanResult {
        var lines: [String] = []
        for image in images {
            lines += try await recognizeLines(in: image)
        }
        let date = findDate(in: lines)
        let known = matchKnownFirms(lines: lines, firmNames: knownFirmNames)
        let candidates = lines.filter(isCandidate)
        return ScanResult(lines: unique(candidates), knownFirms: known, date: date)
    }

    private static func recognizeLines(in image: UIImage) async throws -> [String] {
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
            return sorted.compactMap { $0.topCandidates(1).first?.string }
        }.value
    }

    /// Szuka znanych firm w tekście (porównanie bez polskich znaków i wielkości liter).
    static func matchKnownFirms(lines: [String], firmNames: [String]) -> [String] {
        let lineKeys = lines.map { "_" + Firm.key(for: $0) + "_" }
        var found: [(Int, String)] = []
        for name in firmNames {
            let key = "_" + Firm.key(for: name) + "_"
            guard key.count > 2 else { continue }
            if let idx = lineKeys.firstIndex(where: { $0.contains(key) }) {
                found.append((idx, name))
            }
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
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

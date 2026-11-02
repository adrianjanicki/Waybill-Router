import UIKit
import Observation
import SwiftData

/// Stan edytora kursu trzymany poza oknem, żeby przeciągnięcie okna w dół
/// nie gubiło danych – kurs chowa się na pasek na dole ekranu.
@Observable
final class TripDraft {
    var date = Date()
    var firmNames: [String] = []
    var kmText = ""
    var durationSeconds = 0
    var scanLines: [String] = []
    var newFirm = ""
    var status: String?
    var loaded = false
    /// Zapisany albo świadomie odrzucony – nie ma czego przywracać.
    var finished = false

    /// Czy jest coś, co by przepadło po zamknięciu bez zapisu.
    func hasChanges(trip: Trip?, images: [UIImage]) -> Bool {
        if !newFirm.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        if let trip {
            return trip.date != date || trip.firmNames != firmNames || Fmt.km(trip.km) != kmText
        }
        return !images.isEmpty || !firmNames.isEmpty || !kmText.isEmpty
    }

    /// Krótki opis na pasek „wróć do kursu”.
    var summary: String {
        if firmNames.isEmpty { return "Kurs bez firm" }
        let firms = firmNames.map { $0.uppercased() }.joined(separator: ", ")
        return kmText.isEmpty ? firms : "\(firms) · \(kmText) km"
    }
}

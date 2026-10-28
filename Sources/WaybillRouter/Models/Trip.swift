import Foundation
import SwiftData

/// Jeden kurs: Magazyn → firmy (w kolejności jazdy) → Magazyn.
@Model
final class Trip {
    var date: Date
    var firmNames: [String]
    var km: Double
    var durationSeconds: Int
    var created: Date

    init(date: Date, firmNames: [String], km: Double, durationSeconds: Int = 0) {
        self.date = date
        self.firmNames = firmNames
        self.km = km
        self.durationSeconds = durationSeconds
        self.created = .now
    }

    var routeDescription: String {
        (["Magazyn"] + firmNames.map { $0.uppercased() } + ["Magazyn"]).joined(separator: " – ")
    }
}

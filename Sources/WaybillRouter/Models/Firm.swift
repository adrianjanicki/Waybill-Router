import Foundation
import SwiftData

/// Firma z listu przewozowego. Adres podaje się raz, potem jest zapamiętany.
@Model
final class Firm {
    @Attribute(.unique) var key: String
    var name: String
    var address: String
    var lat: Double
    var lon: Double

    init(name: String, address: String, lat: Double, lon: Double) {
        self.key = Firm.key(for: name)
        self.name = Firm.normalized(name)
        self.address = address
        self.lat = lat
        self.lon = lon
    }

    static func normalized(_ s: String) -> String {
        s.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Klucz bez polskich znaków i interpunkcji, żeby "Team for Print" == "TEAM FOR PRINT".
    static func key(for name: String) -> String {
        normalized(name)
            .replacingOccurrences(of: "ł", with: "l")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(separator: " ")
            .joined(separator: "_")
    }
}

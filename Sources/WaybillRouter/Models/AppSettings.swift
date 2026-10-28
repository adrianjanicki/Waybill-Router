import Foundation

/// Klucze ustawień zapisywanych w UserDefaults (@AppStorage).
enum SettingsKey {
    static let apiKey = "tomtomApiKey"
    static let rate = "ratePerKm"
    static let carrier = "carrier"
    static let car = "car"
    static let registration = "registration"
    static let depotAddress = "depotAddress"
    static let depotLat = "depotLat"
    static let depotLon = "depotLon"
    static let truckProfile = "truckProfile"
}

enum Defaults {
    static let carrier = "USŁUGI TRANSPORTOWE TOMASZ KRÓLAK"
    static let car = "PEUGEOT BOXER"
    static let registration = "WI 094JM"
    static let depotAddress = "Sun Chemical, Okólna, 05-270 Marki"
    static let depotLat = 52.338
    static let depotLon = 21.1011

    static func register() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.carrier: carrier,
            SettingsKey.car: car,
            SettingsKey.registration: registration,
            SettingsKey.depotAddress: depotAddress,
            SettingsKey.depotLat: depotLat,
            SettingsKey.depotLon: depotLon,
            SettingsKey.truckProfile: true,
            SettingsKey.rate: 0.0,
        ])
    }

    /// Klucz TomTom: najpierw z Ustawień aplikacji, potem wbudowany przez build_and_install.sh.
    static var tomTomKey: String {
        let fromSettings = UserDefaults.standard.string(forKey: SettingsKey.apiKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromSettings.isEmpty { return fromSettings }
        return (Bundle.main.object(forInfoDictionaryKey: "TomTomAPIKey") as? String) ?? ""
    }
}

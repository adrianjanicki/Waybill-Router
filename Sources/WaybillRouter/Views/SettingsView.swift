import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Firm.name) private var firms: [Firm]

    @AppStorage(SettingsKey.apiKey) private var apiKey = ""
    @AppStorage(SettingsKey.rate) private var rate = 0.0
    @AppStorage(SettingsKey.carrier) private var carrier = Defaults.carrier
    @AppStorage(SettingsKey.car) private var car = Defaults.car
    @AppStorage(SettingsKey.registration) private var registration = Defaults.registration
    @AppStorage(SettingsKey.depotAddress) private var depotAddress = Defaults.depotAddress
    @AppStorage(SettingsKey.depotLat) private var depotLat = Defaults.depotLat
    @AppStorage(SettingsKey.depotLon) private var depotLon = Defaults.depotLon
    @AppStorage(SettingsKey.truckProfile) private var truckProfile = true

    @State private var depotQuery = ""
    @State private var depotMessage: String?
    @State private var editFirm: AddressTarget?

    private var builtInKey: Bool {
        !((Bundle.main.object(forInfoDictionaryKey: "TomTomAPIKey") as? String) ?? "").isEmpty
    }

    var body: some View {
        Form {
            Section {
                SecureField(builtInKey ? "Wbudowany w aplikację" : "Wklej klucz", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Klucz TomTom API")
            } footer: {
                Text("Darmowy klucz: developer.tomtom.com. Wpisany tutaj ma pierwszeństwo przed wbudowanym.")
            }

            Section("Rozliczenie") {
                HStack {
                    Text("Stawka zł/km")
                    TextField("np. 1,20", value: $rate, format: .number.locale(Fmt.pl))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Karta drogowa") {
                TextField("Przewoźnik", text: $carrier)
                TextField("Marka pojazdu", text: $car)
                TextField("Numer rejestracyjny", text: $registration)
            }

            Section {
                Text(depotAddress)
                TextField("Nowy adres magazynu", text: $depotQuery)
                Button("Zmień magazyn") { Task { await changeDepot() } }
                    .disabled(depotQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                if let depotMessage { Text(depotMessage).font(.footnote).foregroundStyle(.secondary) }
            } header: {
                Text("Magazyn (start i koniec trasy)")
            }

            Section {
                Toggle("Profil ciężarowy (truck)", isOn: $truckProfile)
            } header: {
                Text("Trasa")
            } footer: {
                Text("Włączony: TomTom liczy trasę dla pojazdu dostawczego 3,5 t (omija m.in. drogi z zakazem dla ciężarówek). Zawsze omijane: promy i drogi nieutwardzone.")
            }

            Section {
                if firms.isEmpty {
                    Text("Jeszcze brak. Adresy dodają się przy pierwszym kursie do danej firmy.")
                        .foregroundStyle(.secondary)
                }
                ForEach(firms) { firm in
                    Button { editFirm = AddressTarget(name: firm.name) } label: {
                        VStack(alignment: .leading) {
                            Text(firm.name.uppercased()).foregroundStyle(.primary)
                            Text(firm.address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(firms[i]) }
                }
            } header: {
                Text("Adresy firm")
            }
        }
        .navigationTitle("Ustawienia")
        .sheet(item: $editFirm) { target in
            FirmAddressSheet(
                name: target.name,
                initialAddress: firms.first(where: { $0.name == target.name })?.address ?? target.name
            )
        }
    }

    private func changeDepot() async {
        depotMessage = "Szukam…"
        do {
            if let hit = try await TomTomService().geocode(depotQuery, near: Coordinate(lat: depotLat, lon: depotLon)) {
                depotAddress = hit.label
                depotLat = hit.coordinate.lat
                depotLon = hit.coordinate.lon
                depotQuery = ""
                depotMessage = "Zapisano nowy magazyn."
            } else {
                depotMessage = "Nie znalazłem tego adresu."
            }
        } catch {
            depotMessage = error.localizedDescription
        }
    }
}

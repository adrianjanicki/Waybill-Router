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
        List {
            VStack(alignment: .leading, spacing: 16) {
                WaybillPanelTitle(title: "Rozliczenie", icon: "creditcard")
                HStack(alignment: .firstTextBaseline) {
                    TextField("1,20", value: $rate, format: .number.locale(Fmt.pl))
                        .keyboardType(.decimalPad)
                        .font(.largeTitle.bold().monospacedDigit())
                        .accessibilityLabel("Stawka za kilometr")
                    Text("zł / km").foregroundStyle(.secondary)
                }
                Text("Stawka do podsumowania należności za kursy.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .waybillPanel().waybillPanelRow()

            VStack(alignment: .leading, spacing: 14) {
                WaybillPanelTitle(title: "Przewoźnik i pojazd", icon: "truck.box")
                settingsField("Przewoźnik", text: $carrier)
                Divider()
                settingsField("Marka pojazdu", text: $car)
                Divider()
                settingsField("Numer rejestracyjny", text: $registration)
            }
            .waybillPanel().waybillPanelRow()

            VStack(alignment: .leading, spacing: 14) {
                WaybillPanelTitle(title: "Magazyn", icon: "building.2")
                Text(depotAddress).font(.subheadline)
                Text("Początek i koniec trasy").font(.caption).foregroundStyle(.secondary)
                Divider()
                TextField("Nowy adres magazynu", text: $depotQuery, axis: .vertical)
                    .padding(12)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                Button { Task { await changeDepot() } } label: {
                    Label("Zmień magazyn", systemImage: "mappin.and.ellipse")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .secondaryActionStyle()
                .tint(.white)
                .disabled(depotQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                if let depotMessage {
                    Text(depotMessage).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .waybillPanel().waybillPanelRow()

            VStack(alignment: .leading, spacing: 12) {
                WaybillPanelTitle(title: "Planowanie trasy", icon: "point.topleft.down.to.point.bottomright.curvepath")
                Toggle("Profil ciężarowy", isOn: $truckProfile)
                Text("Trasa dla pojazdu dostawczego 3,5 t. Uwzględnia zakazy dla ciężarówek. Promy i drogi nieutwardzone są zawsze omijane.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .waybillPanel().waybillPanelRow()

            VStack(alignment: .leading, spacing: 12) {
                WaybillPanelTitle(title: "Połączenie z TomTom", icon: "key")
                SecureField(builtInKey ? "Wbudowany w aplikację" : "Wklej klucz API", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Klucz TomTom API")
                Text("Własny klucz zastępuje klucz wbudowany. Uzyskasz go na developer.tomtom.com.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .waybillPanel().waybillPanelRow()

            Section {
                if firms.isEmpty {
                    Text("Adresy pojawią się po dodaniu pierwszych firm.")
                        .foregroundStyle(.secondary)
                        .waybillPanel().waybillPanelRow()
                }
                ForEach(firms) { firm in
                    Button { editFirm = AddressTarget(name: firm.name) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "building.2").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(firm.name.uppercased()).font(.subheadline.weight(.semibold))
                                Text(firm.address).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                        .waybillPanel()
                    }
                    .buttonStyle(.plain)
                    .waybillPanelRow()
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(firms[i]) }
                }
            } header: {
                Text("Adresy firm").font(.headline).textCase(nil)
            }

            NavigationLink { LogView() } label: {
                Label("Dziennik zdarzeń", systemImage: "list.bullet.rectangle")
                    .foregroundStyle(.primary)
            }
            .waybillPanel().waybillPanelRow()
        }
        .listStyle(.plain)
        .appScreen()
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("Ustawienia")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editFirm) { target in
            FirmAddressSheet(
                name: target.name,
                initialAddress: firms.first(where: { $0.name == target.name })?.address ?? target.name
            )
        }
    }

    private func settingsField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text, axis: .vertical)
                .font(.body.weight(.medium))
                .padding(12)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
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

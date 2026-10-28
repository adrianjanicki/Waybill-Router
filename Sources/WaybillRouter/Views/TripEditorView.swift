import SwiftUI
import SwiftData

/// Nowy kurs (ze skanu lub ręcznie) albo edycja zapisanego.
struct TripEditorView: View {
    var trip: Trip?
    var images: [UIImage]
    var initialDate: Date = .now
    var onSaved: (Date) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Firm.name) private var firms: [Firm]

    @AppStorage(SettingsKey.depotLat) private var depotLat = Defaults.depotLat
    @AppStorage(SettingsKey.depotLon) private var depotLon = Defaults.depotLon

    @State private var date = Date()
    @State private var firmNames: [String] = []
    @State private var kmText = ""
    @State private var durationSeconds = 0
    @State private var scanLines: [String] = []
    @State private var newFirm = ""
    @State private var status: String?
    @State private var working = false
    @State private var addressFor: AddressTarget?
    @State private var loaded = false

    private var firmsByKey: [String: Firm] {
        Dictionary(firms.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }
    private var missing: [String] { firmNames.filter { firmsByKey[Firm.key(for: $0)] == nil } }
    private var km: Double? { Double(kmText.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            Form {
                if working && !images.isEmpty && scanLines.isEmpty {
                    Section { HStack { ProgressView(); Text("Odczytuję list przewozowy…") } }
                }

                Section {
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                        .environment(\.locale, Fmt.pl)
                }

                Section {
                    ForEach(firmNames, id: \.self) { name in
                        firmRow(name)
                    }
                    .onDelete { firmNames.remove(atOffsets: $0); kmText = "" }
                    HStack {
                        TextField("Dodaj firmę", text: $newFirm)
                            .textInputAutocapitalization(.characters)
                            .onSubmit(addTypedFirm)
                        Button("Dodaj", action: addTypedFirm).disabled(newFirm.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Firmy z listu")
                } footer: {
                    Text("Kolejność ułoży się sama po przeliczeniu trasy. Adres nowej firmy podajesz tylko raz.")
                }

                let suggestions = scanLines.filter { line in !firmNames.contains { Firm.key(for: $0) == Firm.key(for: line) } }
                if !suggestions.isEmpty {
                    Section("Tekst z dokumentu – dotknij, żeby dodać firmę") {
                        ForEach(suggestions, id: \.self) { line in
                            Button {
                                firmNames.append(Firm.normalized(ScanService.stripRowNumber(line)))
                                kmText = ""
                            } label: {
                                Label(line, systemImage: "plus.circle")
                            }
                        }
                    }
                }

                Section {
                    Button {
                        Task { await computeRoute() }
                    } label: {
                        HStack {
                            Text("Przelicz trasę (TomTom)")
                            if working && !firmNames.isEmpty { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(firmNames.isEmpty || !missing.isEmpty || working)

                    HStack {
                        Text("Kilometry")
                        TextField("0", text: $kmText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title3.monospacedDigit())
                    }
                    if durationSeconds > 0 {
                        LabeledContent("Czas jazdy", value: Fmt.duration(durationSeconds))
                    }
                    if let status {
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Trasa")
                } footer: {
                    Text((["Magazyn"] + firmNames.map { $0.uppercased() } + ["Magazyn"]).joined(separator: " – "))
                }
            }
            .navigationTitle(trip == nil ? "Nowy kurs" : "Edytuj kurs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz", action: save).disabled(firmNames.isEmpty || (km ?? 0) <= 0)
                }
            }
            .sheet(item: $addressFor) { target in
                FirmAddressSheet(name: target.name, initialAddress: target.name) {
                    if missing.isEmpty { Task { await computeRoute() } }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func firmRow(_ name: String) -> some View {
        if let firm = firmsByKey[Firm.key(for: name)] {
            VStack(alignment: .leading) {
                Text(name.uppercased()).font(.body.weight(.semibold))
                Text(firm.address).font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Button {
                addressFor = AddressTarget(name: name)
            } label: {
                VStack(alignment: .leading) {
                    Text(name.uppercased()).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Label("Podaj adres (tylko raz)", systemImage: "mappin.and.ellipse").font(.caption)
                }
            }
        }
    }

    private func addTypedFirm() {
        let name = Firm.normalized(newFirm)
        guard !name.isEmpty, !firmNames.contains(where: { Firm.key(for: $0) == Firm.key(for: name) }) else { return }
        firmNames.append(name)
        newFirm = ""
        kmText = ""
    }

    private func load() async {
        guard !loaded else { return }
        loaded = true
        date = initialDate
        if let trip {
            date = trip.date
            firmNames = trip.firmNames
            kmText = Fmt.km(trip.km)
            durationSeconds = trip.durationSeconds
            return
        }
        guard !images.isEmpty else { return }
        working = true
        defer { working = false }
        do {
            let result = try await ScanService.recognize(images: images, knownFirmNames: firms.map(\.name))
            if let d = result.date { date = d }
            firmNames = result.routeFirms
            scanLines = result.lines
            status = result.routeFirms.isEmpty
                ? "Nie znalazłem kolumny „Trasa”. Dotknij nazw firm z dokumentu poniżej albo wpisz je."
                : "Firmy z kolumny „Trasa”: \(result.routeFirms.count). Sprawdź listę i datę."
        } catch {
            status = "Nie udało się odczytać dokumentu: \(error.localizedDescription)"
            AppLog.log("Skan: błąd OCR: \(error.localizedDescription)")
        }
        if !firmNames.isEmpty && missing.isEmpty {
            working = false
            await computeRoute()
        }
    }

    private func computeRoute() async {
        let byKey = firmsByKey
        let stops = firmNames.compactMap { byKey[Firm.key(for: $0)] }
        guard !stops.isEmpty, stops.count == firmNames.count else { return }
        working = true
        defer { working = false }
        status = "Układam trasę i liczę kilometry…"
        do {
            let result = try await TomTomService().route(
                depot: Coordinate(lat: depotLat, lon: depotLon),
                stops: stops.map { Coordinate(lat: $0.lat, lon: $0.lon) }
            )
            firmNames = result.order.map { firmNames[$0] }
            kmText = Fmt.km((Double(result.lengthMeters) / 1000).rounded())
            durationSeconds = result.travelSeconds
            status = "Trasa ułożona: \(kmText) km według TomTom."
            AppLog.log("Trasa: \(firmNames.joined(separator: " → ")) = \(kmText) km")
        } catch {
            status = "Nie udało się policzyć trasy: \(error.localizedDescription). Możesz wpisać kilometry ręcznie."
            AppLog.log("Trasa: błąd TomTom: \(error.localizedDescription)")
        }
    }

    private func save() {
        guard let km else { return }
        if let trip {
            trip.date = date
            trip.firmNames = firmNames
            trip.km = km
            trip.durationSeconds = durationSeconds
        } else {
            context.insert(Trip(date: date, firmNames: firmNames, km: km, durationSeconds: durationSeconds))
        }
        do {
            try context.save()
        } catch {
            AppLog.log("Zapis kursu: błąd: \(error.localizedDescription)")
        }
        let total = (try? context.fetchCount(FetchDescriptor<Trip>())) ?? -1
        AppLog.log("\(trip == nil ? "Nowy kurs" : "Zmieniony kurs") \(Fmt.full(date)): \(firmNames.joined(separator: ", ")), \(Fmt.km(km)) km. Kursów w bazie: \(total)")
        onSaved(date)
        dismiss()
    }
}

struct AddressTarget: Identifiable {
    var name: String
    var id: String { name }
}

/// Wyszukanie i zapamiętanie adresu firmy.
struct FirmAddressSheet: View {
    var name: String
    var initialAddress: String
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.depotLat) private var depotLat = Defaults.depotLat
    @AppStorage(SettingsKey.depotLon) private var depotLon = Defaults.depotLon

    @State private var query = ""
    @State private var results: [GeocodeHit] = []
    @State private var hit: GeocodeHit?
    @State private var message: String?
    @State private var searching = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("nazwa firmy, ulica, miasto", text: $query)
                            .autocorrectionDisabled()
                        if searching { ProgressView() }
                    }
                } header: {
                    Text("Adres firmy \(name.uppercased())")
                } footer: {
                    Text("Propozycje pojawiają się w trakcie pisania. Dotknij właściwej i zapisz.")
                }
                if !results.isEmpty {
                    Section("Propozycje") {
                        ForEach(results, id: \.self) { r in
                            Button { hit = r } label: {
                                HStack {
                                    Text(r.label).foregroundStyle(.primary)
                                    Spacer()
                                    if hit == r { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                            }
                        }
                    }
                }
                if let message {
                    Text(message).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Adres firmy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Zapisz", action: save).disabled(hit == nil) }
            }
            .onAppear { if query.isEmpty { query = initialAddress } }
            .task(id: query) {
                // Krótka pauza, żeby nie pytać TomTom o każdą literę.
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await search()
            }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        searching = true
        defer { searching = false }
        do {
            let found = try await TomTomService().search(q, near: Coordinate(lat: depotLat, lon: depotLon))
            guard !Task.isCancelled else { return }
            results = found
            if let hit, !found.contains(hit) { self.hit = nil }
            if found.count == 1 { hit = found[0] }
            message = found.isEmpty ? "Brak propozycji. Spróbuj inaczej, np. sama nazwa firmy albo ulica z miastem." : nil
        } catch {
            guard !Task.isCancelled else { return }
            message = error.localizedDescription
        }
    }

    private func save() {
        guard let hit else { return }
        let key = Firm.key(for: name)
        let existing = try? context.fetch(FetchDescriptor<Firm>(predicate: #Predicate<Firm> { $0.key == key })).first
        if let existing {
            existing.address = hit.label
            existing.lat = hit.coordinate.lat
            existing.lon = hit.coordinate.lon
        } else {
            context.insert(Firm(name: name, address: hit.label, lat: hit.coordinate.lat, lon: hit.coordinate.lon))
        }
        try? context.save()
        AppLog.log("Adres firmy \(name.uppercased()): \(hit.label)")
        onSaved()
        dismiss()
    }
}

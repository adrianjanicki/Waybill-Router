import SwiftUI
import SwiftData

/// Nowy kurs (ze skanu lub ręcznie) albo edycja zapisanego.
struct TripEditorView: View {
    var trip: Trip?
    var images: [UIImage]
    var initialDate: Date = .now
    @Bindable var draft: TripDraft = TripDraft()
    var onSaved: (Date) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Firm.name) private var firms: [Firm]

    @AppStorage(SettingsKey.depotLat) private var depotLat = Defaults.depotLat
    @AppStorage(SettingsKey.depotLon) private var depotLon = Defaults.depotLon
    @AppStorage(SettingsKey.keepOrder) private var keepOrder = false

    @State private var working = false
    @State private var addressFor: AddressTarget?
    @State private var editMode: EditMode = .inactive
    @State private var confirmDiscard = false

    private var firmsByKey: [String: Firm] {
        Dictionary(firms.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }
    private var missing: [String] { draft.firmNames.filter { firmsByKey[Firm.key(for: $0)] == nil } }
    private var km: Double? { Double(draft.kmText.replacingOccurrences(of: ",", with: ".")) }

    private var hasChanges: Bool { draft.hasChanges(trip: trip, images: images) }

    var body: some View {
        NavigationStack {
            Form {
                if working && !images.isEmpty && draft.scanLines.isEmpty {
                    Section { HStack { ProgressView(); Text("Odczytuję list przewozowy…") } }
                }

                Section {
                    DatePicker("Data", selection: $draft.date, displayedComponents: .date)
                        .environment(\.locale, Fmt.pl)
                }

                Section {
                    ForEach(draft.firmNames, id: \.self) { name in
                        firmRow(name)
                    }
                    .onDelete { draft.firmNames.remove(atOffsets: $0); draft.kmText = "" }
                    .onMove { draft.firmNames.move(fromOffsets: $0, toOffset: $1); draft.kmText = "" }
                    HStack {
                        TextField("Dodaj firmę", text: $draft.newFirm)
                            .textInputAutocapitalization(.characters)
                            .onSubmit(addTypedFirm)
                        Button("Dodaj", action: addTypedFirm).disabled(draft.newFirm.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    HStack {
                        Text("Firmy z listu")
                        Spacer()
                        if draft.firmNames.count > 1 {
                            Button(editMode.isEditing ? "Gotowe" : "Zmień kolejność") {
                                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                            }
                            .font(.footnote)
                            .textCase(nil)
                        }
                    }
                } footer: {
                    Text(keepOrder
                         ? "Trasa pojedzie w tej kolejności, w jakiej są firmy na liście. Kolejność zmienisz przyciskiem „Zmień kolejność” (przeciągnij firmę za uchwyt). Adres nowej firmy podajesz tylko raz."
                         : "Kolejność ułoży się sama po przeliczeniu trasy. Adres nowej firmy podajesz tylko raz.")
                }

                let suggestions = draft.scanLines.filter { line in !draft.firmNames.contains { Firm.key(for: $0) == Firm.key(for: line) } }
                if !suggestions.isEmpty {
                    Section("Tekst z dokumentu – dotknij, żeby dodać firmę") {
                        ForEach(suggestions, id: \.self) { line in
                            Button {
                                draft.firmNames.append(Firm.normalized(ScanService.stripRowNumber(line)))
                                draft.kmText = ""
                            } label: {
                                Label(line, systemImage: "plus.circle")
                            }
                        }
                    }
                }

                Section {
                    Toggle("Pomiń optymalizację", isOn: $keepOrder)
                        .onChange(of: keepOrder) {
                            draft.kmText = ""
                            if !draft.firmNames.isEmpty && missing.isEmpty { Task { await computeRoute() } }
                        }
                    Button {
                        Task { await computeRoute() }
                    } label: {
                        HStack {
                            Text("Przelicz trasę (TomTom)")
                            if working && !draft.firmNames.isEmpty { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(draft.firmNames.isEmpty || !missing.isEmpty || working)

                    HStack {
                        Text("Kilometry")
                        TextField("0", text: $draft.kmText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title3.monospacedDigit())
                    }
                    if draft.durationSeconds > 0 {
                        LabeledContent("Czas jazdy", value: Fmt.duration(draft.durationSeconds))
                    }
                    if let status = draft.status {
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Trasa")
                } footer: {
                    Text((["Magazyn"] + draft.firmNames.map { $0.uppercased() } + ["Magazyn"]).joined(separator: " – "))
                }
            }
            .navigationTitle(trip == nil ? "Nowy kurs" : "Edytuj kurs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") {
                        if hasChanges { confirmDiscard = true } else { draft.finished = true; dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz", action: save).disabled(draft.firmNames.isEmpty || (km ?? 0) <= 0)
                }
            }
            .confirmationDialog("Zamknąć bez zapisywania?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Odrzuć zmiany", role: .destructive) {
                    AppLog.log("Edytor kursu zamknięty bez zapisu: \(draft.firmNames.joined(separator: ", "))")
                    draft.finished = true
                    dismiss()
                }
                Button("Wróć do edycji", role: .cancel) {}
            } message: {
                Text("Firmy i kilometry z tego kursu nie zostaną zapisane.")
            }
            .sheet(item: $addressFor) { target in
                FirmAddressSheet(name: target.name, initialAddress: target.name) {
                    if missing.isEmpty { Task { await computeRoute() } }
                }
            }
            .environment(\.editMode, $editMode)
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
        let name = Firm.normalized(draft.newFirm)
        guard !name.isEmpty, !draft.firmNames.contains(where: { Firm.key(for: $0) == Firm.key(for: name) }) else { return }
        draft.firmNames.append(name)
        draft.newFirm = ""
        draft.kmText = ""
    }

    private func load() async {
        guard !draft.loaded else { return }
        draft.loaded = true
        draft.date = initialDate
        if let trip {
            draft.date = trip.date
            draft.firmNames = trip.firmNames
            draft.kmText = Fmt.km(trip.km)
            draft.durationSeconds = trip.durationSeconds
            return
        }
        guard !images.isEmpty else { return }
        working = true
        defer { working = false }
        do {
            let result = try await ScanService.recognize(images: images, knownFirmNames: firms.map(\.name))
            if let d = result.date { draft.date = d }
            draft.firmNames = result.routeFirms
            draft.scanLines = result.lines
            draft.status = result.routeFirms.isEmpty
                ? "Nie znalazłem kolumny „Trasa”. Dotknij nazw firm z dokumentu poniżej albo wpisz je."
                : "Firmy z kolumny „Trasa”: \(result.routeFirms.count). Sprawdź listę i datę."
        } catch {
            // Okno schowane w trakcie skanu – po powrocie skan ruszy od nowa.
            if Task.isCancelled { draft.loaded = false; return }
            draft.status = "Nie udało się odczytać dokumentu: \(error.localizedDescription)"
            AppLog.log("Skan: błąd OCR: \(error.localizedDescription)")
        }
        if !draft.firmNames.isEmpty && missing.isEmpty {
            working = false
            await computeRoute()
        }
    }

    private func computeRoute() async {
        let byKey = firmsByKey
        let stops = draft.firmNames.compactMap { byKey[Firm.key(for: $0)] }
        guard !stops.isEmpty, stops.count == draft.firmNames.count else { return }
        working = true
        defer { working = false }
        let optimize = !keepOrder
        draft.status = optimize ? "Układam trasę i liczę kilometry…" : "Liczę kilometry we wpisanej kolejności…"
        do {
            let names = draft.firmNames
            let result = try await TomTomService().route(
                depot: Coordinate(lat: depotLat, lon: depotLon),
                stops: stops.map { Coordinate(lat: $0.lat, lon: $0.lon) },
                optimize: optimize
            )
            // Lista albo przełącznik mogły się zmienić w trakcie zapytania – wtedy wynik jest nieaktualny.
            guard names == draft.firmNames, optimize == !keepOrder else { return }
            draft.firmNames = result.order.map { names[$0] }
            draft.kmText = Fmt.km((Double(result.lengthMeters) / 1000).rounded())
            draft.durationSeconds = result.travelSeconds
            draft.status = optimize
                ? "Trasa ułożona: \(draft.kmText) km według TomTom."
                : "Trasa we wpisanej kolejności: \(draft.kmText) km według TomTom."
            AppLog.log("Trasa\(optimize ? "" : " (bez optymalizacji)"): \(draft.firmNames.joined(separator: " → ")) = \(draft.kmText) km")
        } catch {
            draft.status = "Nie udało się policzyć trasy: \(error.localizedDescription). Możesz wpisać kilometry ręcznie."
            AppLog.log("Trasa: błąd TomTom: \(error.localizedDescription)")
        }
    }

    private func save() {
        guard let km else { return }
        if let trip {
            trip.date = draft.date
            trip.firmNames = draft.firmNames
            trip.km = km
            trip.durationSeconds = draft.durationSeconds
        } else {
            context.insert(Trip(date: draft.date, firmNames: draft.firmNames, km: km, durationSeconds: draft.durationSeconds))
        }
        do {
            try context.save()
        } catch {
            AppLog.log("Zapis kursu: błąd: \(error.localizedDescription)")
        }
        let total = (try? context.fetchCount(FetchDescriptor<Trip>())) ?? -1
        AppLog.log("\(trip == nil ? "Nowy kurs" : "Zmieniony kurs") \(Fmt.full(draft.date)): \(draft.firmNames.joined(separator: ", ")), \(Fmt.km(km)) km. Kursów w bazie: \(total)")
        draft.finished = true
        onSaved(draft.date)
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
            .interactiveDismissDisabled(hit != nil)
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

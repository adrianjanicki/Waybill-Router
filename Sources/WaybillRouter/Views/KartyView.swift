import SwiftUI

/// Karty drogowe miesiąca po 15 kursów + ręczne poprawki + eksport PDF / Word / CSV.
struct KartyView: View {
    var month: Date
    var trips: [Trip]

    @AppStorage(SettingsKey.carrier) private var carrier = Defaults.carrier
    @AppStorage(SettingsKey.car) private var car = Defaults.car
    @AppStorage(SettingsKey.registration) private var registration = Defaults.registration
    @AppStorage(SettingsKey.rate) private var rate = 0.0

    @State private var edits: KartaEdits
    @State private var editing: RowTarget?
    @State private var editingHeader = false
    @State private var confirmReset = false
    @State private var pdfURL: URL?
    @State private var docxURL: URL?
    @State private var csvURL: URL?
    @State private var error: String?

    init(month: Date, trips: [Trip]) {
        self.month = month
        self.trips = trips
        _edits = State(initialValue: KartaEdits.load(month: month))
    }

    private var defaultHeader: KartaHeader {
        KartaHeader(carrier: carrier, car: car, registration: registration)
    }
    private var header: KartaHeader { edits.header(defaults: defaultHeader) }
    private var rows: [KartaRow] { edits.rows(for: trips) }
    private var cards: [[KartaRow]] { rows.chunked(KartaExport.tripsPerCard) }

    /// Zmiana czegokolwiek, co trafia do plików, odświeża eksport.
    private var exportKey: ExportKey { ExportKey(rows: rows, header: header, rate: rate) }

    var body: some View {
        List {
            VStack(spacing: 12) {
                Text(Fmt.month(month)).font(.headline)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .glass(in: Capsule(), interactive: false)
                Text("\(Fmt.km(rows.reduce(0) { $0 + $1.km })) km")
                    .font(.largeTitle.bold().monospacedDigit())
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text("\(Plural.pl(rows.count, "kurs", "kursy", "kursów")) · \(Plural.pl(cards.count, "karta", "karty", "kart"))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .waybillPanelRow()

            if trips.isEmpty {
                ContentUnavailableView("Brak kart", systemImage: "doc.text",
                                       description: Text("Dodaj kursy w tym miesiącu, aby przygotować karty drogowe."))
                    .waybillPanelRow()
            } else {
                if let error {
                    Text(error).foregroundStyle(.red).waybillPanel().waybillPanelRow()
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        WaybillPanelTitle(title: "Dane na karcie", icon: "truck.box")
                        Spacer()
                        Button { editingHeader = true } label: {
                            Image(systemName: "pencil").frame(width: 44, height: 44)
                        }
                        .secondaryActionStyle()
                        .tint(.white)
                        .accessibilityLabel("Edytuj nagłówek karty")
                    }
                    Text(header.carrier).font(.headline)
                    Label(header.car, systemImage: "car.side").font(.subheadline)
                    Text(header.registration).font(.subheadline.monospaced().weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.primary.opacity(0.05), in: Capsule())
                    if !edits.isEmpty {
                        Divider()
                        Button("Cofnij wszystkie poprawki", role: .destructive) { confirmReset = true }
                            .font(.subheadline)
                    }
                }
                .waybillPanel().waybillPanelRow()
            }

            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                Section {
                    ForEach(Array(card.enumerated()), id: \.offset) { j, row in
                        Button {
                            editing = RowTarget(trip: trips[index * KartaExport.tripsPerCard + j])
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(Fmt.dayMonth(row.date)).font(.headline.monospacedDigit())
                                    Text("· \(j + 1)").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    if row.edited {
                                        Image(systemName: "pencil").foregroundStyle(.orange)
                                            .accessibilityLabel("Wiersz poprawiony")
                                    }
                                    Text("\(Fmt.km(row.km)) km").font(.headline.monospacedDigit())
                                }
                                Text(row.description)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(.primary)
                            .waybillPanel()
                        }
                        .buttonStyle(.plain)
                        .waybillPanelRow()
                        .accessibilityHint("Edytuj datę, opis trasy i kilometry")
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Karta \(index + 1)").font(.title3.weight(.semibold))
                        Text("\(Fmt.dayMonth(card.first!.date)) – \(Fmt.dayMonth(card.last!.date)) · \(Fmt.km(card.reduce(0) { $0 + $1.km })) km")
                            .font(.caption)
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .appScreen()
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("Karty drogowe")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !trips.isEmpty {
                exportMenu
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
        }
        .onChange(of: edits) { _, new in new.save(month: month) }
        .task(id: exportKey) { export() }
        .sheet(item: $editing) { target in
            KartaRowEditor(trip: target.trip, edit: edits.rows[KartaEdits.key(for: target.trip)] ?? KartaRowEdit()) {
                edits.set($0, for: target.trip)
            }
        }
        .sheet(isPresented: $editingHeader) {
            KartaHeaderEditor(edits: $edits, defaults: defaultHeader)
        }
        .confirmationDialog("Cofnąć wszystkie poprawki kart z tego miesiąca?", isPresented: $confirmReset,
                            titleVisibility: .visible) {
            Button("Cofnij poprawki", role: .destructive) { edits = KartaEdits() }
        }
    }

    /// Jedno menu „Eksportuj” zamiast trzech osobnych przycisków.
    private var exportMenu: some View {
        Menu {
            if let pdfURL {
                ShareLink(item: pdfURL) { Label("PDF – do wydruku", systemImage: "doc.richtext") }
            }
            if let docxURL {
                ShareLink(item: docxURL) { Label("Word – do edycji", systemImage: "doc.text") }
            }
            if let csvURL {
                ShareLink(item: csvURL) { Label("CSV – do Excela", systemImage: "tablecells") }
            }
        } label: {
            Label("Eksportuj", systemImage: "square.and.arrow.up")
                .labelStyle(.titleAndIcon)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .prominentActionStyle()
        .tint(.orange)
        .buttonBorderShape(.capsule)
        .disabled(trips.isEmpty || pdfURL == nil)
    }

    private func export() {
        guard !rows.isEmpty else { return }
        do {
            pdfURL = try KartaExport.pdf(rows: rows, header: header, month: month)
            docxURL = try KartaExport.docx(rows: rows, header: header, month: month)
            csvURL = try KartaExport.csv(rows: rows, month: month, rate: rate)
            error = nil
        } catch {
            self.error = "Nie udało się przygotować plików: \(error.localizedDescription)"
            AppLog.log("Błąd eksportu kart: \(error.localizedDescription)")
        }
    }
}

private struct ExportKey: Equatable {
    var rows: [KartaRow]
    var header: KartaHeader
    var rate: Double
}

private struct RowTarget: Identifiable {
    let id = UUID()
    var trip: Trip
}

/// Poprawka jednego wiersza karty (tylko na karcie, kurs zostaje bez zmian).
private struct KartaRowEditor: View {
    var trip: Trip
    var edit: KartaRowEdit
    var onSave: (KartaRowEdit) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var text = ""
    @State private var kmText = ""

    private var km: Double? { Double(kmText.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                }
                Section("Opis trasy + nazwa firmy") {
                    TextField("Opis", text: $text, axis: .vertical).lineLimit(2...6)
                }
                Section("Kilometry") {
                    TextField("0", text: $kmText).keyboardType(.decimalPad)
                }
                Section {
                    Button("Przywróć dane z kursu") {
                        date = trip.date
                        text = trip.routeDescription
                        kmText = Fmt.km(trip.km)
                    }
                } footer: {
                    Text("Zmiany dotyczą tylko karty drogowej (PDF, Word, CSV). Sam kurs i jego trasa zostają bez zmian.")
                }
            }
            .appScreen()
            .keyboardDismissable()
            .navigationTitle("Wiersz karty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz", action: save).saveButtonStyle().disabled(km == nil)
                }
            }
            .onAppear {
                date = edit.date ?? trip.date
                text = edit.description ?? trip.routeDescription
                kmText = Fmt.km(edit.km ?? trip.km)
            }
        }
    }

    private func save() {
        guard let km else { return }
        var new = KartaRowEdit()
        if !Calendar.current.isDate(date, inSameDayAs: trip.date) { new.date = date }
        if text != trip.routeDescription { new.description = text }
        if km != trip.km { new.km = km }
        onSave(new)
        AppLog.log("Poprawka karty, kurs \(Fmt.full(trip.date)): \(new.isEmpty ? "przywrócono dane z kursu" : "\(Fmt.full(date)), \(text), \(Fmt.km(km)) km")")
        dismiss()
    }
}

/// Nagłówek karty dla tego miesiąca (domyślnie z Ustawień).
private struct KartaHeaderEditor: View {
    @Binding var edits: KartaEdits
    var defaults: KartaHeader

    @Environment(\.dismiss) private var dismiss
    @State private var carrier = ""
    @State private var car = ""
    @State private var registration = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Przewoźnik", text: $carrier, axis: .vertical)
                    TextField("Marka pojazdu", text: $car)
                    TextField("Numer rejestracyjny", text: $registration)
                } footer: {
                    Text("Dotyczy tylko kart z tego miesiąca. Stałe dane zmienisz w Ustawieniach.")
                }
                Section {
                    Button("Przywróć z Ustawień") {
                        carrier = defaults.carrier
                        car = defaults.car
                        registration = defaults.registration
                    }
                }
            }
            .appScreen()
            .keyboardDismissable()
            .navigationTitle("Nagłówek karty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        edits.carrier = carrier == defaults.carrier ? nil : carrier
                        edits.car = car == defaults.car ? nil : car
                        edits.registration = registration == defaults.registration ? nil : registration
                        dismiss()
                    }
                    .saveButtonStyle()
                }
            }
            .onAppear {
                let h = edits.header(defaults: defaults)
                carrier = h.carrier
                car = h.car
                registration = h.registration
            }
        }
    }
}

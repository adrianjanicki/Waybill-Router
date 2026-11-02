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
            if trips.isEmpty {
                Text("Karty pojawią się po dodaniu kursów w tym miesiącu.").foregroundStyle(.secondary)
            } else {
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }

                Section {
                    Button { editingHeader = true } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(header.carrier).font(.subheadline.weight(.semibold))
                            Text("\(header.car) · \(header.registration)").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    if !edits.isEmpty {
                        Button("Cofnij wszystkie poprawki", role: .destructive) { confirmReset = true }
                    }
                } header: {
                    Text("Nagłówek karty")
                } footer: {
                    Text("Stuknij wiersz karty, żeby poprawić datę, opis trasy lub kilometry. Gotowe karty wyślesz przyciskiem Eksportuj (PDF, Word, CSV).")
                }
            }
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                Section {
                    ForEach(Array(card.enumerated()), id: \.offset) { j, row in
                        Button {
                            editing = RowTarget(trip: trips[index * KartaExport.tripsPerCard + j])
                        } label: {
                            HStack(alignment: .top) {
                                Text("\(j + 1).").monospacedDigit().foregroundStyle(.secondary)
                                Text(Fmt.dayMonth(row.date)).monospacedDigit()
                                Text(row.description).font(.footnote)
                                Spacer()
                                if row.edited {
                                    Image(systemName: "pencil").font(.caption).foregroundStyle(.orange)
                                }
                                Text(Fmt.km(row.km)).monospacedDigit()
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    HStack {
                        Text("Karta \(index + 1): \(Fmt.dayMonth(card.first!.date)) – \(Fmt.dayMonth(card.last!.date))")
                        Spacer()
                        Text("\(Fmt.km(card.reduce(0) { $0 + $1.km })) km")
                    }
                }
            }
        }
        .navigationTitle(Fmt.month(month))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { exportMenu }
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
        }
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

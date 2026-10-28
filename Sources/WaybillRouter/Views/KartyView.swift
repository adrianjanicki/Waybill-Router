import SwiftUI

/// Karty drogowe miesiąca po 15 kursów + eksport PDF/CSV.
struct KartyView: View {
    var month: Date
    var trips: [Trip]

    @AppStorage(SettingsKey.carrier) private var carrier = Defaults.carrier
    @AppStorage(SettingsKey.car) private var car = Defaults.car
    @AppStorage(SettingsKey.registration) private var registration = Defaults.registration
    @AppStorage(SettingsKey.rate) private var rate = 0.0

    @State private var pdfURL: URL?
    @State private var csvURL: URL?
    @State private var error: String?

    private var cards: [[Trip]] { trips.chunked(KartaExport.tripsPerCard) }

    var body: some View {
        List {
            if trips.isEmpty {
                Text("Karty pojawią się po dodaniu kursów w tym miesiącu.").foregroundStyle(.secondary)
            } else {
                Section {
                    if let pdfURL {
                        ShareLink(item: pdfURL) { Label("Karty drogowe (PDF)", systemImage: "doc.richtext") }
                    }
                    if let csvURL {
                        ShareLink(item: csvURL) { Label("Zestawienie do Excela (CSV)", systemImage: "tablecells") }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                Section {
                    ForEach(Array(card.enumerated()), id: \.offset) { j, t in
                        HStack(alignment: .top) {
                            Text("\(j + 1).").monospacedDigit().foregroundStyle(.secondary)
                            Text(Fmt.dayMonth(t.date)).monospacedDigit()
                            Text(t.routeDescription).font(.footnote)
                            Spacer()
                            Text(Fmt.km(t.km)).monospacedDigit()
                        }
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
        .task(id: trips.count) { export() }
    }

    private func export() {
        guard !trips.isEmpty else { return }
        do {
            let header = KartaHeader(carrier: carrier, car: car, registration: registration)
            pdfURL = try KartaExport.pdf(trips: trips, header: header, month: month)
            csvURL = try KartaExport.csv(trips: trips, month: month, rate: rate)
        } catch {
            self.error = "Nie udało się przygotować plików: \(error.localizedDescription)"
        }
    }
}

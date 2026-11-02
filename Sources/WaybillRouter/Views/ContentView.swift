import SwiftUI
import SwiftData
import PhotosUI

/// Co otwieramy w edytorze kursu.
struct EditorTarget: Identifiable {
    let id = UUID()
    var trip: Trip?
    var images: [UIImage] = []
    /// Domyślna data nowego kursu.
    var date: Date = .now
    /// Wpisane dane – przeżywają schowanie okna gestem w dół.
    let draft = TripDraft()

    /// Czy po zamknięciu okna jest co przywracać.
    var shouldPark: Bool {
        draft.loaded && !draft.finished && draft.hasChanges(trip: trip, images: images)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Trip.date), SortDescriptor(\Trip.created)]) private var allTrips: [Trip]
    @AppStorage(SettingsKey.rate) private var rate = 0.0

    @State private var month = Date().startOfMonth
    @State private var showScanner = false
    @State private var photoItem: PhotosPickerItem?
    @State private var editor: EditorTarget?
    @State private var tripToDelete: Trip?
    @State private var scannedImages: [UIImage] = []
    /// Kursy schowane przeciągnięciem w dół – czekają na pasku na dole.
    @State private var parked: [EditorTarget] = []
    @State private var parkedToDiscard: EditorTarget?

    private var monthTrips: [Trip] { allTrips.filter { $0.date.isSameMonth(as: month) } }
    private var monthKm: Double { monthTrips.reduce(0) { $0 + $1.km } }

    /// Inne miesiące, w których są kursy (żeby kurs zapisany z inną datą nie „znikał”).
    private var otherMonths: [MonthSummary] {
        let grouped = Dictionary(grouping: allTrips) { $0.date.startOfMonth }
        return grouped
            .filter { !$0.key.isSameMonth(as: month) }
            .map { MonthSummary(month: $0.key, count: $0.value.count, km: $0.value.reduce(0) { $0 + $1.km }) }
            .sorted { $0.month > $1.month }
    }

    /// Nowy kurs ręcznie: w bieżącym miesiącu dzisiejsza data, w innym – data ostatniego kursu z tego miesiąca.
    private var newTripDate: Date {
        if month.isSameMonth(as: .now) { return .now }
        return monthTrips.last?.date ?? month
    }

    var body: some View {
        NavigationStack {
            List {
                Section { summary }

                Section {
                    Button {
                        if DocumentScanner.isSupported { showScanner = true }
                    } label: {
                        Label("Skanuj listę przewozową", systemImage: "doc.viewfinder")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!DocumentScanner.isSupported)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Wybierz zdjęcie z galerii", systemImage: "photo")
                    }
                    Button {
                        editor = EditorTarget(date: newTripDate)
                    } label: {
                        Label("Dodaj kurs ręcznie", systemImage: "square.and.pencil")
                    }
                }

                Section("Kursy – \(Fmt.month(month))") {
                    if monthTrips.isEmpty {
                        Text("Brak kursów w tym miesiącu. Zeskanuj list przewozowy, żeby dodać pierwszy.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(monthTrips) { trip in
                        Button { editor = EditorTarget(trip: trip) } label: { TripRow(trip: trip) }
                            .foregroundStyle(.primary)
                            .swipeActions {
                                Button("Usuń", role: .destructive) { tripToDelete = trip }
                            }
                    }
                }

                if !otherMonths.isEmpty {
                    Section("Inne miesiące z kursami") {
                        ForEach(otherMonths) { item in
                            Button { month = item.month } label: {
                                HStack {
                                    Text(Fmt.month(item.month))
                                    Spacer()
                                    Text("\(item.count) kurs. · \(Fmt.km(item.km)) km")
                                        .monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !parked.isEmpty { parkedBar }
            }
            .navigationTitle("Karta drogowa")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { KartyView(month: month, trips: monthTrips) } label: {
                        Label("Karty", systemImage: "doc.text")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: {
                        Label("Ustawienia", systemImage: "gearshape")
                    }
                }
            }
            .fullScreenCover(isPresented: $showScanner, onDismiss: {
                // Edytor otwieramy dopiero po zamknięciu skanera (dwa modale naraz nie działają).
                if !scannedImages.isEmpty {
                    editor = EditorTarget(images: scannedImages)
                    scannedImages = []
                }
            }) {
                DocumentScanner { images in
                    scannedImages = images
                    showScanner = false
                } onCancel: {
                    showScanner = false
                }
                .ignoresSafeArea()
            }
            .sheet(item: $editor) { target in
                TripEditorView(trip: target.trip, images: target.images, initialDate: target.date, draft: target.draft) { savedDate in
                    month = savedDate.startOfMonth
                }
                .onDisappear {
                    // Przeciągnięte w dół bez zapisu – chowamy na pasek zamiast gubić.
                    if target.shouldPark && !parked.contains(where: { $0.id == target.id }) {
                        withAnimation { parked.append(target) }
                        AppLog.log("Kurs schowany na pasek: \(target.draft.summary)")
                    }
                }
            }
            .onAppear {
                AppLog.log("Start aplikacji. Kursów w bazie: \(allTrips.count)")
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        editor = EditorTarget(images: [image])
                    }
                    photoItem = nil
                }
            }
            .confirmationDialog("Odrzucić niezapisany kurs?", isPresented: Binding(
                get: { parkedToDiscard != nil }, set: { if !$0 { parkedToDiscard = nil } }
            ), titleVisibility: .visible) {
                Button("Odrzuć", role: .destructive) {
                    if let t = parkedToDiscard {
                        AppLog.log("Odrzucono schowany kurs: \(t.draft.summary)")
                        withAnimation { parked.removeAll { $0.id == t.id } }
                    }
                    parkedToDiscard = nil
                }
            } message: {
                Text(parkedToDiscard?.draft.summary ?? "")
            }
            .confirmationDialog("Usunąć ten kurs?", isPresented: Binding(
                get: { tripToDelete != nil }, set: { if !$0 { tripToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Usuń", role: .destructive) {
                    if let t = tripToDelete {
                        AppLog.log("Usunięto kurs \(Fmt.full(t.date)): \(t.firmNames.joined(separator: ", ")), \(Fmt.km(t.km)) km")
                        context.delete(t)
                        try? context.save()
                    }
                    tripToDelete = nil
                }
            }
        }
    }

    /// Pasek z kursami schowanymi gestem – dotknięcie otwiera kurs z powrotem.
    private var parkedBar: some View {
        VStack(spacing: 8) {
            ForEach(parked) { target in
                HStack(spacing: 12) {
                    Button {
                        parked.removeAll { $0.id == target.id }
                        editor = target
                    } label: {
                        HStack {
                            Image(systemName: "chevron.up.circle.fill").font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.trip == nil ? "Niezapisany kurs – wróć" : "Niezapisane zmiany – wróć")
                                    .font(.subheadline.weight(.semibold))
                                Text(target.draft.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { parkedToDiscard = target } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var summary: some View {
        VStack(spacing: 12) {
            HStack {
                Button { month = month.addingMonths(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(Fmt.month(month)).font(.headline)
                Spacer()
                Button { month = month.addingMonths(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.borderless)
            HStack {
                Stat(title: "Kilometry", value: Fmt.km(monthKm))
                Stat(title: "Kursy", value: "\(monthTrips.count)")
                Stat(title: "Do zapłaty", value: rate > 0 ? Fmt.money(monthKm * rate) : "—")
            }
        }
    }
}

private struct MonthSummary: Identifiable {
    var month: Date
    var count: Int
    var km: Double
    var id: Date { month }
}

private struct Stat: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TripRow: View {
    var trip: Trip

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Fmt.dayMonth(trip.date)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            Text(trip.routeDescription).font(.subheadline)
            Spacer(minLength: 8)
            Text("\(Fmt.km(trip.km)) km").font(.subheadline.monospacedDigit().weight(.semibold))
        }
    }
}

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
    /// Nowy kurs (skan, galeria, ręczny) wraca na pasek zawsze, gdy nie został zapisany ani anulowany;
    /// edycja zapisanego kursu – tylko gdy coś w nim zmieniono.
    var shouldPark: Bool {
        guard draft.loaded, !draft.finished else { return false }
        return trip == nil || draft.hasChanges(trip: trip, images: images)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Trip.date), SortDescriptor(\Trip.created)]) private var allTrips: [Trip]
    @Query private var firms: [Firm]
    @AppStorage(SettingsKey.rate) private var rate = 0.0

    @State private var month = Date().startOfMonth
    @State private var showScanner = false
    @State private var photoItem: PhotosPickerItem?
    @State private var editor: EditorTarget?
    @State private var tripToDelete: Trip?
    @State private var scannedImages: [UIImage] = []
    /// Kursy schowane przeciągnięciem w dół – czekają w kapsule na dole.
    @State private var parked: [EditorTarget] = []
    @State private var parkedToDiscard: EditorTarget?
    /// Lista szkiców (gdy schowanych kursów jest kilka).
    @State private var showDrafts = false
    /// Szkic wybrany z listy – otwieramy go dopiero po zamknięciu listy.
    @State private var draftToOpen: EditorTarget?

    private var monthTrips: [Trip] { allTrips.filter { $0.date.isSameMonth(as: month) } }
    /// Na liście kursów najnowszy na górze (data malejąco, w tym samym dniu ostatnio dodany pierwszy).
    private var monthTripsNewestFirst: [Trip] { monthTrips.reversed() }
    private var monthKm: Double { monthTrips.reduce(0) { $0 + $1.km } }
    private var knownFirmKeys: Set<String> { Set(firms.map(\.key)) }

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

                Section { actions }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                Section {
                    if monthTrips.isEmpty {
                        Text("Brak kursów w tym miesiącu. Zeskanuj list przewozowy, żeby dodać pierwszy.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(monthTripsNewestFirst) { trip in
                        Button { editor = EditorTarget(trip: trip) } label: {
                            TripRow(trip: trip, needsAttention: needsAttention(trip))
                        }
                        .foregroundStyle(.primary)
                        .swipeActions {
                            Button("Usuń", role: .destructive) { tripToDelete = trip }
                        }
                    }
                } header: {
                    HStack {
                        Text("Kursy")
                        Spacer()
                        if !monthTrips.isEmpty {
                            Text(Plural.pl(monthTrips.count, "kurs", "kursy", "kursów")).textCase(nil)
                        }
                    }
                }

                if !otherMonths.isEmpty {
                    Section("Inne miesiące z kursami") {
                        ForEach(otherMonths) { item in
                            Button { withAnimation { month = item.month } } label: {
                                HStack {
                                    Text(Fmt.month(item.month))
                                    Spacer()
                                    Text("\(Plural.pl(item.count, "kurs", "kursy", "kursów")) · \(Fmt.km(item.km)) km")
                                        .monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !parked.isEmpty {
                    returnCapsule
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
                    // Przeciągnięte w dół bez zapisu – chowamy do kapsuły zamiast gubić.
                    if target.shouldPark && !parked.contains(where: { $0.id == target.id }) {
                        withAnimation { parked.append(target) }
                        AppLog.log("Kurs schowany na pasek: \(target.draft.summary)")
                    }
                }
            }
            .sheet(isPresented: $showDrafts, onDismiss: {
                // Edytor otwieramy dopiero po zamknięciu listy szkiców.
                if let t = draftToOpen {
                    draftToOpen = nil
                    reopen(t)
                }
            }) {
                DraftsSheet(parked: $parked) { target in
                    draftToOpen = target
                    showDrafts = false
                }
                .presentationDetents([.medium, .large])
            }
            .onChange(of: parked.count) { _, count in
                if count < 2 && showDrafts && draftToOpen == nil { showDrafts = false }
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
                    if let t = parkedToDiscard { discard(t, from: $parked) }
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

    /// Kurs wymaga uwagi: firma bez zapisanego adresu albo brak kilometrów.
    private func needsAttention(_ trip: Trip) -> Bool {
        trip.km <= 0 || trip.firmNames.contains { !knownFirmKeys.contains(Firm.key(for: $0)) }
    }

    private func reopen(_ target: EditorTarget) {
        parked.removeAll { $0.id == target.id }
        editor = target
    }

    // MARK: - Ekran główny

    private var summary: some View {
        VStack(spacing: 14) {
            HStack {
                Button { withAnimation { month = month.addingMonths(-1) } } label: {
                    Image(systemName: "chevron.left").frame(width: 20, height: 20)
                }
                .accessibilityLabel("Poprzedni miesiąc")
                Spacer()
                Text(Fmt.month(month)).font(.title3.weight(.semibold))
                Spacer()
                Button { withAnimation { month = month.addingMonths(1) } } label: {
                    Image(systemName: "chevron.right").frame(width: 20, height: 20)
                }
                .accessibilityLabel("Następny miesiąc")
            }
            .secondaryActionStyle()
            .buttonBorderShape(.circle)
            .tint(.primary)

            HStack(spacing: 0) {
                Stat(title: "Kilometry", value: Fmt.km(monthKm))
                Divider().frame(height: 32)
                Stat(title: "Kursy", value: "\(monthTrips.count)")
                Divider().frame(height: 32)
                Stat(title: "Do zapłaty", value: rate > 0 ? Fmt.money(monthKm * rate) : "—")
            }
        }
        .padding(.vertical, 4)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                if DocumentScanner.isSupported { showScanner = true }
            } label: {
                Label("Skanuj list przewozowy", systemImage: "doc.viewfinder")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .prominentActionStyle()
            .controlSize(.large)
            .tint(.orange)
            .disabled(!DocumentScanner.isSupported)

            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Galeria", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                Button {
                    editor = EditorTarget(date: newTripDate)
                } label: {
                    Label("Dodaj ręcznie", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
            }
            .secondaryActionStyle()
            .controlSize(.large)
            .tint(.primary)
            .font(.subheadline.weight(.medium))
        }
    }

    // MARK: - Kapsuła „Wróć do kursu”

    /// Szklana kapsuła na dole: jeden szkic – dotknięcie wraca do kursu,
    /// kilka szkiców – pokazuje ich liczbę i otwiera listę do wyboru.
    private var returnCapsule: some View {
        HStack(spacing: 12) {
            Button {
                if parked.count == 1, let only = parked.first { reopen(only) } else { showDrafts = true }
            } label: {
                HStack(spacing: 12) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        if parked.count > 1 {
                            Text("\(parked.count)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.orange, in: Capsule())
                                .offset(x: 8, y: -6)
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Wróć do kursu").font(.subheadline.weight(.semibold))
                        Text(capsuleDetail)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if parked.count > 1 {
                        Image(systemName: "chevron.up").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(parked.count > 1 ? "Otwiera listę niezapisanych kursów" : "Otwiera niezapisany kurs")

            if parked.count == 1, let only = parked.first {
                Button { parkedToDiscard = only } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Odrzuć niezapisany kurs")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .glassCapsule()
    }

    private var capsuleDetail: String {
        if parked.count == 1, let only = parked.first {
            return only.trip == nil ? only.draft.shortSummary : "Zmiany · \(only.draft.shortSummary)"
        }
        return "\(Plural.pl(parked.count, "szkic", "szkice", "szkiców")) – wybierz z listy"
    }
}

/// Odrzucenie schowanego kursu (z kapsuły albo z listy szkiców).
private func discard(_ target: EditorTarget, from parked: Binding<[EditorTarget]>) {
    AppLog.log("Odrzucono schowany kurs: \(target.draft.summary)")
    withAnimation { parked.wrappedValue.removeAll { $0.id == target.id } }
}

/// Lista kilku niezapisanych kursów – dotknięcie wraca do wybranego.
private struct DraftsSheet: View {
    @Binding var parked: [EditorTarget]
    var onOpen: (EditorTarget) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var toDiscard: EditorTarget?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(parked) { target in
                        Button { onOpen(target) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: target.trip == nil ? "doc.badge.plus" : "pencil.circle")
                                    .font(.title3)
                                    .foregroundStyle(.orange)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(target.trip == nil ? "Nowy kurs · \(Fmt.dayMonth(target.draft.date))"
                                                            : "Zmiany w kursie · \(Fmt.dayMonth(target.draft.date))")
                                        .font(.subheadline.weight(.semibold))
                                    Text(target.draft.summary)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .foregroundStyle(.primary)
                        .swipeActions {
                            Button("Odrzuć", role: .destructive) { toDiscard = target }
                        }
                    }
                } footer: {
                    Text("Przesuń szkic w lewo, żeby go odrzucić.")
                }
            }
            .navigationTitle("Niezapisane kursy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Gotowe") { dismiss() } }
            }
            .confirmationDialog("Odrzucić niezapisany kurs?", isPresented: Binding(
                get: { toDiscard != nil }, set: { if !$0 { toDiscard = nil } }
            ), titleVisibility: .visible) {
                Button("Odrzuć", role: .destructive) {
                    if let t = toDiscard { discard(t, from: $parked) }
                    toDiscard = nil
                }
            } message: {
                Text(toDiscard?.draft.summary ?? "")
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
        VStack(spacing: 2) {
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Wiersz kursu: data po lewej, firmy w kolejności jazdy, kilometry po prawej.
private struct TripRow: View {
    var trip: Trip
    var needsAttention: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 0) {
                Text(Fmt.day(trip.date)).font(.title3.weight(.semibold).monospacedDigit())
                Text(Fmt.weekdayShort(trip.date)).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(trip.firmNames.isEmpty ? "—" : trip.firmNames.map { $0.uppercased() }.joined(separator: " → "))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if needsAttention {
                    Label(trip.km <= 0 ? "Brak kilometrów" : "Firma bez adresu", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(Fmt.km(trip.km)).font(.body.weight(.semibold).monospacedDigit())
                Text("km").font(.caption).foregroundStyle(.secondary)
            }
            .foregroundStyle(trip.km <= 0 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Color.primary))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

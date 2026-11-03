import SwiftUI
import SwiftData
import PhotosUI
import UIKit

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
    @ScaledMetric(relativeTo: .largeTitle) private var distanceSize = 104

    @State private var month = Date().startOfMonth
    /// Dzień pokazany na ekranie głównym (przesuwany w lewo/prawo).
    @State private var day = Date().startOfDay
    /// Kierunek ostatniej zmiany dnia – do animacji wjazdu kart.
    @State private var dayStep = 1
    @State private var showScanner = false
    @State private var showKarty = false
    @State private var showSettings = false
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
    /// Kursy wybranego dnia, w kolejności dodania.
    private var dayTrips: [Trip] { allTrips.filter { $0.date.isSameDay(as: day) } }
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

    /// Nowy kurs ręcznie: na dzień, który jest właśnie pokazany.
    private var newTripDate: Date {
        day.isSameDay(as: .now) ? .now : day
    }

    /// Zmiana dnia (gest albo strzałki); miesiąc u góry idzie za dniem.
    private func showDay(_ newDay: Date) {
        let target = newDay.startOfDay
        guard !target.isSameDay(as: day) else { return }
        dayStep = target > day ? 1 : -1
        withAnimation(.spring(duration: 0.3)) {
            day = target
            if !target.isSameMonth(as: month) { month = target.startOfMonth }
        }
    }

    /// Zmiana miesiąca: bieżący – dziś, inny – ostatni dzień z kursem (albo pierwszy dzień miesiąca).
    private func showMonth(_ newMonth: Date) {
        let start = newMonth.startOfMonth
        let target: Date
        if start.isSameMonth(as: .now) {
            target = Date().startOfDay
        } else {
            target = (allTrips.last { $0.date.isSameMonth(as: start) }?.date ?? start).startOfDay
        }
        dayStep = start > month ? 1 : -1
        withAnimation {
            month = start
            day = target
        }
    }

    var body: some View {
        NavigationStack {
            List {
                header
                    .plainRow(top: 4, bottom: 0)

                summary
                    .plainRow(top: 12, bottom: 8)

                dayHeader
                    .plainRow(top: 18, bottom: 4)

                dayCards
                    .plainRow(top: 5, bottom: 5)

                if !otherMonths.isEmpty {
                    Text("Inne miesiące z kursami")
                        .font(.headline)
                        .padding(.horizontal, 6)
                        .plainRow(top: 22, bottom: 4)
                    ForEach(otherMonths) { item in
                        Button { showMonth(item.month) } label: {
                            HStack {
                                Text(Fmt.month(item.month)).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(Plural.pl(item.count, "kurs", "kursy", "kursów")) · \(Fmt.km(item.km)) km")
                                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 18).padding(.vertical, 14)
                            .tripCardBackground()
                        }
                        .buttonStyle(CardPressStyle())
                        .plainRow(top: 4, bottom: 4)
                    }
                }
            }
            .dayPaging { step in showDay(day.addingDays(step)) }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if !parked.isEmpty {
                        returnCapsule
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    dock
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showKarty) { KartyView(month: month, trips: monthTrips) }
            .navigationDestination(isPresented: $showSettings) { SettingsView() }
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
                    day = savedDate.startOfDay
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
        // Projekt ekranu jest ciemny (poświata, szkło), więc aplikacja zawsze w trybie ciemnym.
        .preferredColorScheme(.dark)
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

    /// Tytuł z okrągłymi szklanymi przyciskami: karty (lewo) i ustawienia (prawo).
    private var header: some View {
        HStack {
            Button { showKarty = true } label: {
                Image(systemName: "doc.text")
                    .font(.title3.weight(.medium))
                    .frame(width: 52, height: 52)
                    .glass(in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Karty drogowe")

            Spacer()
            Text("Karta drogowa").font(.title2.weight(.bold))
            Spacer()

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title3.weight(.medium))
                    .frame(width: 52, height: 52)
                    .glass(in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ustawienia")
        }
        .padding(.horizontal, 4)
    }

    private var summary: some View {
        VStack(spacing: 26) {
            // Szklana kapsuła z miesiącem.
            HStack {
                Button { showMonth(month.addingMonths(-1)) } label: {
                    Image(systemName: "chevron.left").font(.headline)
                        .frame(width: 48, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Poprzedni miesiąc")
                Spacer(minLength: 4)
                Text(Fmt.month(month)).font(.title3.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Button { showMonth(month.addingMonths(1)) } label: {
                    Image(systemName: "chevron.right").font(.headline)
                        .frame(width: 48, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Następny miesiąc")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .glass(in: Capsule(), interactive: false)
            .frame(maxWidth: 320)

            // Duża liczba kilometrów.
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.km(monthKm))
                        .font(.system(size: distanceSize, weight: .heavy))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("km")
                        .font(.system(size: distanceSize * 0.36, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .shadow(color: .white.opacity(0.08), radius: 12)
                Text("Przejechane w tym miesiącu")
                    .font(.headline.weight(.regular)).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            // Kursy | Do zapłaty.
            HStack(spacing: 0) {
                Text(Plural.pl(monthTrips.count, "kurs", "kursy", "kursów"))
                    .font(.title.weight(.bold))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 48)
                VStack(spacing: 2) {
                    Text(rate > 0 ? Fmt.money(monthKm * rate) : "—")
                        .font(.title.weight(.bold).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text("Do zapłaty").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Dzień

    /// „Dziś” ze strzałkami; pod spodem liczba kursów i km z tego dnia.
    private var dayHeader: some View {
        let km = dayTrips.reduce(0) { $0 + $1.km }
        return HStack(spacing: 4) {
            Button { showDay(day.addingDays(-1)) } label: {
                Image(systemName: "chevron.left").font(.headline)
                    .frame(width: 40, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Poprzedni dzień")

            VStack(spacing: 2) {
                Text(Fmt.dayTitle(day))
                    .font(.title2.weight(.bold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(Calendar.current.isDateInToday(day) || Calendar.current.isDateInYesterday(day) || Calendar.current.isDateInTomorrow(day)
                     ? "\(Fmt.weekdayDate(day)) · \(dayCountText(km))"
                     : dayCountText(km))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)

            Button { showDay(day.addingDays(1)) } label: {
                Image(systemName: "chevron.right").font(.headline)
                    .frame(width: 40, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Następny dzień")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .glass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
        .overlay(alignment: .bottom) {
            if !Calendar.current.isDateInToday(day) {
                Button { showDay(.now) } label: {
                    Label("Wróć do dziś", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .glass(in: Capsule())
                }
                .buttonStyle(.plain)
                .offset(y: 16)
                .transition(.opacity)
            }
        }
        .padding(.bottom, Calendar.current.isDateInToday(day) ? 0 : 16)
        .contentShape(Rectangle())
    }

    private func dayCountText(_ km: Double) -> String {
        dayTrips.isEmpty ? "brak kursów" : "\(Plural.pl(dayTrips.count, "kurs", "kursy", "kursów")) · \(Fmt.km(km)) km"
    }

    /// Karty kursów z jednego dnia. Przesunięcie w lewo – następny dzień, w prawo – poprzedni.
    private var dayCards: some View {
        VStack(spacing: 10) {
            if dayTrips.isEmpty {
                Text("Brak kursów tego dnia. Przesuń w lewo lub w prawo, żeby zobaczyć inne dni.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .tripCardBackground()
            }
            ForEach(dayTrips) { trip in
                Button { editor = EditorTarget(trip: trip) } label: {
                    TripRow(trip: trip, needsAttention: needsAttention(trip))
                }
                .buttonStyle(CardPressStyle())
                .contextMenu {
                    Button("Usuń kurs", systemImage: "trash", role: .destructive) { tripToDelete = trip }
                }
            }
        }
        .id(day)
        .transition(.asymmetric(
            insertion: .move(edge: dayStep > 0 ? .trailing : .leading).combined(with: .opacity),
            removal: .opacity))
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .top)
        .contentShape(Rectangle())
    }

    /// Szklany dok na dole: Skanuj (pomarańczowy), Galeria, Ręcznie.
    private var dock: some View {
        HStack(spacing: 10) {
            Button {
                if DocumentScanner.isSupported { showScanner = true }
            } label: {
                dockLabel("Skanuj", icon: "camera")
            }
            .buttonStyle(DockButtonStyle(prominent: true))
            .disabled(!DocumentScanner.isSupported)
            .accessibilityLabel("Skanuj list przewozowy")

            PhotosPicker(selection: $photoItem, matching: .images) {
                dockLabel("Galeria", icon: "photo")
            }
            .buttonStyle(DockButtonStyle(prominent: false))

            Button {
                editor = EditorTarget(date: newTripDate)
            } label: {
                dockLabel("Ręcznie", icon: "plus")
            }
            .buttonStyle(DockButtonStyle(prominent: false))
            .accessibilityLabel("Dodaj kurs ręcznie")
        }
        .padding(10)
        .glass(in: RoundedRectangle(cornerRadius: 36, style: .continuous), interactive: false)
    }

    private func dockLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2.weight(.medium))
            Text(title).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 64)
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

/// Karta kursu: data | firmy w kolejności jazdy | kilometry.
private struct TripRow: View {
    var trip: Trip
    var needsAttention: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(spacing: 2) {
                Text(Fmt.day(trip.date)).font(.title.weight(.bold).monospacedDigit())
                Text(Fmt.weekdayShort(trip.date)).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(width: 64)

            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 1)
                .padding(.vertical, 2)
                .padding(.trailing, 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(trip.firmNames.isEmpty ? "—" : trip.firmNames.map { $0.uppercased() }.joined(separator: " → "))
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if needsAttention {
                    Label(trip.km <= 0 ? "Brak kilometrów" : "Firma bez adresu", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(Fmt.km(trip.km)) km")
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .foregroundStyle(trip.km <= 0 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Color.primary))
                .padding(.leading, 10)
        }
        .padding(.vertical, 16)
        .padding(.leading, 8)
        .padding(.trailing, 18)
        .frame(maxWidth: .infinity, minHeight: 92)
        .tripCardBackground()
        .accessibilityElement(children: .combine)
    }
}

/// Przycisk w doku: pomarańczowy (główna akcja) albo szklany.
private struct DockButtonStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        configuration.label
            .foregroundStyle(.white)
            .background {
                if prominent {
                    shape.fill(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.2), Color(red: 0.93, green: 0.45, blue: 0.05)],
                                              startPoint: .top, endPoint: .bottom))
                        .shadow(color: .orange.opacity(isEnabled ? 0.55 : 0), radius: 14, y: 2)
                } else {
                    shape.fill(Color.white.opacity(0.08))
                }
            }
            .overlay(shape.strokeBorder(Color.white.opacity(prominent ? 0.35 : 0.14), lineWidth: 0.75))
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Karta reaguje na dotknięcie lekkim zmniejszeniem.
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

private extension View {
    /// Tło karty kursu: przyciemnione szkło z cienką jasną ramką.
    func tripCardBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return self
            .background(Color.white.opacity(0.06), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75))
            .contentShape(shape)
    }

    /// Wiersz listy bez tła i separatora, z marginesami jak na projekcie.
    func plainRow(top: CGFloat, bottom: CGFloat) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
    }
}


private extension View {
    @ViewBuilder
    func dayPaging(onPage: @escaping (Int) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            self.gesture(HorizontalDayPan(onPage: onPage))
        } else {
            self.simultaneousGesture(
                DragGesture(minimumDistance: 24).onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) >= 44, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                    onPage(dx < 0 ? 1 : -1)
                }
            )
        }
    }
}

@available(iOS 18.0, *)
private struct HorizontalDayPan: UIGestureRecognizerRepresentable {
    let onPage: (Int) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard recognizer.state == .ended else { return }
        let movement = recognizer.translation(in: recognizer.view)
        guard abs(movement.x) >= 44, abs(movement.x) > abs(movement.y) * 1.5 else { return }
        onPage(movement.x < 0 ? 1 : -1)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let movement = pan.translation(in: pan.view)
            return abs(movement.x) > abs(movement.y) * 1.5
        }
    }
}

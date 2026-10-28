#if DEBUG
import SwiftUI
import SwiftData

/// Podgląd w Xcode (Canvas) z przykładowymi danymi, bez instalacji na telefonie.
/// Otwórz projekt: `./preview.sh`, potem ten plik i Editor → Canvas (⌥⌘↩).
/// Dane podglądu są tylko w pamięci – nic nie trafia do telefonu.
enum PreviewData {
    @MainActor
    static let container: ModelContainer = {
        Defaults.register()
        let container = try! ModelContainer(
            for: Trip.self, Firm.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let firms: [(String, String, Double, Double)] = [
            ("kossacki", "Kossacki, Warszawa", 52.25, 21.0),
            ("asg", "ASG, Ząbki", 52.29, 21.10),
            ("mm", "MM, Wołomin", 52.34, 21.24),
            ("sealed air", "Sealed Air, Warszawa", 52.18, 20.95),
        ]
        for f in firms { ctx.insert(Firm(name: f.0, address: f.1, lat: f.2, lon: f.3)) }
        let cal = Calendar.current
        let now = Date()
        let samples: [(Int, [String], Double)] = [
            (-6, ["kossacki", "asg", "mm"], 84),
            (-4, ["sealed air", "kossacki"], 61),
            (-2, ["asg", "mm", "sealed air"], 97),
        ]
        for s in samples {
            let d = cal.date(byAdding: .day, value: s.0, to: now) ?? now
            ctx.insert(Trip(date: d, firmNames: s.1, km: s.2, durationSeconds: 5400))
        }
        // Kurs z innego miesiąca, żeby było widać listę „Inne miesiące z kursami”.
        ctx.insert(Trip(date: now.addingMonths(-1), firmNames: ["mm"], km: 42))
        return container
    }()
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().modelContainer(PreviewData.container)
    }
}

struct TripEditor_Previews: PreviewProvider {
    static var previews: some View {
        TripEditorView(trip: nil, images: []) { _ in }
            .modelContainer(PreviewData.container)
    }
}

struct Settings_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { SettingsView() }.modelContainer(PreviewData.container)
    }
}
#endif

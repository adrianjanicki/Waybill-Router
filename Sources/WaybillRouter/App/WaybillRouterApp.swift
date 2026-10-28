import SwiftUI
import SwiftData

@main
struct WaybillRouterApp: App {
    init() {
        Defaults.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Trip.self, Firm.self])
    }
}

import SwiftUI

/// Liquid Glass (iOS 26) z zapasowym wyglądem dla starszych systemów.
/// `#if compiler(>=6.2)` – starszy Xcode (bez SDK iOS 26) też to skompiluje,
/// tylko bez szkła; na iOS 17–18 widać materiał/klasyczne przyciski.
extension View {
    /// Szklana kapsuła pływająca nad treścią (np. pasek „Wróć do kursu”).
    @ViewBuilder
    func glassCapsule() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            materialCapsule()
        }
        #else
        materialCapsule()
        #endif
    }

    private func materialCapsule() -> some View {
        self
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    /// Główna akcja ekranu – wypełniony przycisk (szkło na iOS 26).
    @ViewBuilder
    func prominentActionStyle() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
        #else
        self.buttonStyle(.borderedProminent)
        #endif
    }

    /// „Zapisz” w pasku okna – wyraźny, wypełniony przycisk.
    func saveButtonStyle() -> some View {
        prominentActionStyle().tint(.orange)
    }

    /// Akcja drugorzędna – spokojny przycisk (szkło na iOS 26).
    @ViewBuilder
    func secondaryActionStyle() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
        #else
        self.buttonStyle(.bordered)
        #endif
    }
}

enum Plural {
    /// Polska odmiana: 1 firma, 2–4 firmy, 5+ firm (12–14 firm).
    static func pl(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        if n == 1 { return "\(n) \(one)" }
        let mod10 = n % 10, mod100 = n % 100
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "\(n) \(few)" }
        return "\(n) \(many)"
    }
}

extension View {
    /// Szkło w dowolnym kształcie (okrągłe przyciski, karty, dok).
    /// Na starszych systemach – materiał z delikatną ramką.
    @ViewBuilder
    func glass<S: Shape>(in shape: S, interactive: Bool = true) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            materialShape(shape)
        }
        #else
        materialShape(shape)
        #endif
    }

    private func materialShape<S: Shape>(_ shape: S) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

/// Ciemne tło z ciepłą pomarańczową poświatą od dołu.
struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.09), Color(white: 0.04)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.orange.opacity(0.30), Color.orange.opacity(0.08), .clear],
                           center: .bottom, startRadius: 10, endRadius: 520)
            RadialGradient(colors: [Color.orange.opacity(0.07), .clear],
                           center: .top, startRadius: 0, endRadius: 360)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Wspólny wygląd ekranów z listą (Karty, Ustawienia, Dziennik):
    /// to samo ciemne tło z poświatą co ekran główny, ciemne karty sekcji, pomarańczowy akcent.
    func appScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .tint(.orange)
    }
}

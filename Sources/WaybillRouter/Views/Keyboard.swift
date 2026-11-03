import SwiftUI
import UIKit

/// Chowanie klawiatury w całej aplikacji.
///
/// 1. Dotknięcie gdziekolwiek poza polem tekstowym chowa klawiaturę
///    (jeden rozpoznawacz gestów na każdym oknie – działa też w arkuszach).
///    Dotknięty przycisk / przełącznik nadal działa normalnie.
/// 2. Przewinięcie listy w dół chowa klawiaturę (`.keyboardDismissable()`).
/// 3. Nad klawiaturą jest przycisk „Gotowe” – ważne przy klawiaturze
///    numerycznej, która nie ma klawisza Return.
enum KeyboardDismiss {
    @MainActor
    static func hide() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Instaluje gest na wszystkich oknach (bezpieczne do wielokrotnego wywołania).
    @MainActor
    static func installTapToDismiss() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                let already = window.gestureRecognizers?.contains { $0.name == TapToDismissHandler.name } ?? false
                if already { continue }
                let tap = UITapGestureRecognizer(target: TapToDismissHandler.shared,
                                                 action: #selector(TapToDismissHandler.handleTap(_:)))
                tap.name = TapToDismissHandler.name
                tap.cancelsTouchesInView = false
                tap.delaysTouchesBegan = false
                tap.delaysTouchesEnded = false
                tap.delegate = TapToDismissHandler.shared
                window.addGestureRecognizer(tap)
            }
        }
    }
}

@MainActor
private final class TapToDismissHandler: NSObject, UIGestureRecognizerDelegate {
    static let shared = TapToDismissHandler()
    static let name = "WaybillRouter.tapToDismissKeyboard"

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        recognizer.view?.endEditing(true)
    }

    /// Dotknięcie samego pola tekstowego nie chowa klawiatury (np. przejście do innego pola).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let v = view {
            if v is UITextField || v is UITextView { return false }
            view = v.superview
        }
        return true
    }

    /// Nie blokuje innych gestów (przyciski, przewijanie, przełączniki).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

extension View {
    /// Przewinięcie chowa klawiaturę + przycisk „Gotowe” nad klawiaturą.
    func keyboardDismissable() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Gotowe") { KeyboardDismiss.hide() }
                        .fontWeight(.semibold)
                }
            }
    }

    /// Gest „dotknij poza polem” – podpinany raz, przy głównym widoku.
    func installsTapToDismissKeyboard() -> some View {
        onAppear { KeyboardDismiss.installTapToDismiss() }
    }
}

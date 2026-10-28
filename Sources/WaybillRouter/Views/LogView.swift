import SwiftUI

/// Podgląd dziennika zdarzeń (AppLog) z możliwością wysłania i wyczyszczenia.
struct LogView: View {
    @State private var text = ""
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "Dziennik jest pusty." : text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .defaultScrollAnchor(.bottom)
        .navigationTitle("Dziennik zdarzeń")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !text.isEmpty {
                    ShareLink(item: AppLog.fileURL) { Image(systemName: "square.and.arrow.up") }
                    Button(role: .destructive) { confirmClear = true } label: { Image(systemName: "trash") }
                }
            }
        }
        .confirmationDialog("Wyczyścić dziennik?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Wyczyść", role: .destructive) {
                AppLog.clear()
                text = ""
            }
        }
        .onAppear { text = AppLog.read() }
    }
}

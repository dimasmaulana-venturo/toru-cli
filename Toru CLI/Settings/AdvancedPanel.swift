import SwiftUI

struct AdvancedPanel: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var showCleared = false

    var body: some View {
        Form {
            Section("History") {
                Stepper("Size limit: \(settings.historyLimit)",
                        value: $settings.historyLimit, in: 100...100_000, step: 1000)
                Button(role: .destructive) {
                    HistoryDatabase.shared.clear()
                    showCleared = true
                } label: {
                    Label("Clear all history", systemImage: "trash")
                }
                .alert("History cleared", isPresented: $showCleared) {
                    Button("OK", role: .cancel) {}
                }
            }
        }
        .formStyle(.grouped)
    }
}

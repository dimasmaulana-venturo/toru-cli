import SwiftUI

struct KeyboardPanel: View {
    private let bindings: [(String, String)] = [
        ("→ / Tab",   "Accept ghost text"),
        ("Escape",    "Dismiss ghost / popup"),
        ("Ctrl+R",    "History fuzzy search"),
        ("⌘T",        "New tab"),
        ("⌘W",        "Close tab"),
        ("⌘D",        "Split horizontal"),
        ("⌘⇧D",       "Split vertical"),
        ("⌘,",        "Settings"),
        ("⌘+ / ⌘-",   "Font size"),
        ("⌘K",        "Clear buffer"),
        ("⌘⇧C",       "Copy"),
        ("⌘⇧V",       "Paste"),
    ]

    var body: some View {
        Form {
            Section("Bindings") {
                ForEach(bindings, id: \.0) { row in
                    LabeledContent(row.0) {
                        Text(row.1).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

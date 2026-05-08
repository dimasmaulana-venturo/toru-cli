import Foundation
import Combine

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published private(set) var themes: [Theme] = []
    @Published var current: Theme

    private static let builtinNames = [
        "dark", "light", "solarized-dark", "tokyo-night", "one-dark"
    ]

    init() {
        let loaded = Self.loadBuiltins()
        self.themes = loaded
        self.current = loaded.first ?? Self.fallback()
    }

    func select(name: String) {
        if let t = themes.first(where: { $0.name.lowercased() == name.lowercased() }) {
            current = t
        }
    }

    private static func loadBuiltins() -> [Theme] {
        var out: [Theme] = []
        for n in builtinNames {
            guard
                let url = Bundle.main.url(forResource: n, withExtension: "json", subdirectory: "builtin")
                       ?? Bundle.main.url(forResource: n, withExtension: "json"),
                let data = try? Data(contentsOf: url),
                let theme = try? JSONDecoder().decode(Theme.self, from: data)
            else { continue }
            out.append(theme)
        }
        return out.isEmpty ? [fallback()] : out
    }

    private static func fallback() -> Theme {
        Theme(
            name: "Dark",
            background: "#1a1a1a",
            foreground: "#e6e6e6",
            cursor: "#ffffff",
            ansi: [
                "#000000","#cd3131","#0dbc79","#e5e510","#2472c8","#bc3fbc","#11a8cd","#e5e5e5",
                "#666666","#f14c4c","#23d18b","#f5f543","#3b8eea","#d670d6","#29b8db","#ffffff"
            ]
        )
    }
}

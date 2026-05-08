import Foundation
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var fontName: String {
        didSet { UserDefaults.standard.set(fontName, forKey: "fontName") }
    }

    @Published var fontSize: Int {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }

    @Published var themeName: String {
        didSet { UserDefaults.standard.set(themeName, forKey: "themeName") }
    }

    @Published var ghostTextEnabled: Bool {
        didSet { UserDefaults.standard.set(ghostTextEnabled, forKey: "ghostTextEnabled") }
    }

    @Published var tabCompletionEnabled: Bool {
        didSet { UserDefaults.standard.set(tabCompletionEnabled, forKey: "tabCompletionEnabled") }
    }

    @Published var cursorStyle: String {
        didSet { UserDefaults.standard.set(cursorStyle, forKey: "cursorStyle") }
    }

    @Published var historyLimit: Int {
        didSet { UserDefaults.standard.set(historyLimit, forKey: "historyLimit") }
    }

    private init() {
        let d = UserDefaults.standard
        self.fontName = d.string(forKey: "fontName") ?? "Menlo"
        self.fontSize = (d.object(forKey: "fontSize") as? Int) ?? 13
        self.themeName = d.string(forKey: "themeName") ?? "Tokyo Night"
        self.ghostTextEnabled = (d.object(forKey: "ghostTextEnabled") as? Bool) ?? true
        self.tabCompletionEnabled = (d.object(forKey: "tabCompletionEnabled") as? Bool) ?? true
        self.cursorStyle = d.string(forKey: "cursorStyle") ?? "block"
        self.historyLimit = (d.object(forKey: "historyLimit") as? Int) ?? 10_000
    }
}

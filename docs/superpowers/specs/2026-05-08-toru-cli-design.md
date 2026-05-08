# Toru CLI — Design Spec

**Date:** 2026-05-08
**Author:** Dimas Maulana
**Source PRD:** `PRD-MacTerminal.md`
**Status:** Approved (brainstorming → implementation)

---

## 1. Summary

Toru CLI is a native macOS terminal emulator written in Swift + SwiftUI + AppKit. It wraps SwiftTerm for VT100 emulation, adds fish-style inline autocomplete from local SQLite history, and supports `#` line-comment skipping. Distributed as a notarized DMG, open source, no App Store, no sandbox.

Not a Warp clone. No AI, no cloud, no account. 100% local.

---

## 2. Decisions Locked in Brainstorming

| Decision | Choice | Reason |
|---|---|---|
| Distribution | Notarized DMG, open source | No App Store; no sandbox needed; PTY works freely |
| App / bundle name | `Toru CLI` | Xcode project already initialized under this name |
| Default shell | Auto-detect `$SHELL` env var, fallback `/bin/zsh` | Respect user's system default, deterministic fallback |
| Terminal integration | Hybrid (Approach C) — subclass `LocalProcessTerminalView`, override `send()` | Cleanest input intercept; no PTY rewrite |
| Persistence | SQLite via GRDB.swift | PRD spec; well-supported Swift ORM |
| Min macOS | 14 (Sonoma) | PRD spec |
| Swift / Xcode | Swift 5.10+, Xcode 16+ | PRD spec |

---

## 3. Architecture

### 3.1 Layered View

```
┌──────────────────────────────────────────────┐
│  SwiftUI Layer                                │
│   TorApp → WindowGroup → NavigationSplitView │
│   ContentView, SidebarView, TabBarView        │
└──────────────────────┬───────────────────────┘
                       │
┌──────────────────────▼───────────────────────┐
│  AppKit Bridge                                │
│   TorTerminalContainer (NSViewRepresentable)  │
└──────────────────────┬───────────────────────┘
                       │
┌──────────────────────▼───────────────────────┐
│  TorTerminalView : LocalProcessTerminalView   │
│   override send() — input pipeline hook       │
│   GhostTextOverlay (NSTextField subview)      │
└──────────────────────┬───────────────────────┘
                       │
┌──────────────────────▼───────────────────────┐
│  Input Pipeline                               │
│   CommentFilter → AutocompleteEngine → PTY    │
└──────────────────────┬───────────────────────┘
                       │
┌──────────────────────▼───────────────────────┐
│  Persistence                                  │
│   HistoryDatabase (GRDB) — CommandHistory     │
│   ThemeManager — JSON themes                  │
│   SettingsStore — UserDefaults                │
└──────────────────────────────────────────────┘
```

### 3.2 Module Boundaries

| Module | Responsibility | Public API |
|---|---|---|
| `App` | Entry point, scenes, menu bar | `Toru_CLIApp.body` |
| `Terminal` | SwiftTerm wrapper, PTY, VT100 | `TorTerminalView`, `TorTerminalContainer` |
| `Input` | Strip comments, suggest completions | `CommentFilter.filter(_:)`, `AutocompleteEngine.suggest(_:)` |
| `History` | SQLite read/write, dedup | `HistoryDatabase.record(_:)`, `.search(_:)` |
| `UI` | Window chrome, tabs, sidebar | SwiftUI views |
| `Settings` | Settings scene, persistence | `SettingsStore`, `SettingsView` |
| `Themes` | Load/apply ANSI palettes | `ThemeManager.apply(_:)` |

### 3.3 Input Pipeline (Hybrid Approach C)

```
keyDown(NSEvent) → TorTerminalView.send(data:)
   ├─ Enter pressed:
   │     buffer = currentLineBuffer
   │     filtered = CommentFilter.filter(buffer)
   │     if filtered != nil:
   │         HistoryDatabase.record(rawInput: buffer, executed: filtered)
   │         super.send(data: filtered.utf8 + "\n")
   │     else:
   │         super.send(data: "\n")
   ├─ regular key:
   │     super.send(data: keyData)
   │     suggestion = AutocompleteEngine.suggest(currentLine)
   │     GhostTextOverlay.show(suggestion)
   ├─ Right-Arrow / Tab + suggestion:
   │     super.send(data: suggestion.utf8)
   │     GhostTextOverlay.hide()
   └─ Escape:
         GhostTextOverlay.hide()
```

---

## 4. File Layout

```
Toru CLI/
├── Toru CLI/
│   ├── App/
│   │   ├── Toru_CLIApp.swift
│   │   ├── AppDelegate.swift
│   │   └── MenuCommands.swift
│   ├── Terminal/
│   │   ├── TorTerminalView.swift
│   │   ├── TorTerminalContainer.swift
│   │   ├── PTYBridge.swift
│   │   └── GhostTextOverlay.swift
│   ├── Input/
│   │   ├── CommentFilter.swift
│   │   ├── AutocompleteEngine.swift
│   │   └── TabCompleter.swift
│   ├── History/
│   │   ├── HistoryDatabase.swift
│   │   ├── CommandHistory.swift
│   │   └── HistorySearch.swift
│   ├── UI/
│   │   ├── ContentView.swift
│   │   ├── SidebarView.swift
│   │   ├── TabBarView.swift
│   │   └── SplitPaneView.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── GeneralPanel.swift
│   │   ├── AppearancePanel.swift
│   │   ├── AutocompletePanel.swift
│   │   ├── KeyboardPanel.swift
│   │   └── SettingsStore.swift
│   ├── Themes/
│   │   ├── ThemeManager.swift
│   │   ├── Theme.swift
│   │   └── builtin/
│   │       ├── dark.json
│   │       ├── light.json
│   │       ├── solarized-dark.json
│   │       ├── tokyo-night.json
│   │       └── one-dark.json
│   └── Toru_CLI.entitlements
├── Toru CLITests/
│   ├── CommentFilterTests.swift
│   ├── AutocompleteEngineTests.swift
│   └── HistoryDatabaseTests.swift
└── Toru CLIUITests/
    └── Toru_CLIUITests.swift
```

---

## 5. Data Model

```swift
struct CommandHistory: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var command: String
    var rawInput: String
    var directory: String
    var exitCode: Int
    var executedAt: Date
    var sessionId: UUID
}
```

```sql
CREATE TABLE commandHistory (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    command TEXT NOT NULL,
    rawInput TEXT NOT NULL,
    directory TEXT NOT NULL,
    exitCode INTEGER NOT NULL,
    executedAt DATETIME NOT NULL,
    sessionId TEXT NOT NULL
);
CREATE INDEX idx_history_executedAt ON commandHistory(executedAt DESC);
CREATE INDEX idx_history_command_prefix ON commandHistory(command);
```

---

## 6. Comment Filter Spec

```swift
enum CommentFilter {
    static func filter(_ input: String) -> String? {
        let lines = input.components(separatedBy: "\n")
        let kept = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#")
        }
        return kept.isEmpty ? nil : kept.joined(separator: "\n")
    }
}
```

| Input | Output |
|---|---|
| `bun build` | `bun build` |
| `# note` | `nil` |
| `  # indented` | `nil` |
| `bun build # inline` | `bun build # inline` (untouched) |
| `# a\nbun build\n# b` | `bun build` |
| `#!/bin/zsh` | `nil` |
| `## double` | `nil` |

---

## 7. Autocomplete Spec

### Ghost Text
- Trigger: input ≥ 2 chars
- Source: most-recent `commandHistory.command LIKE '<input>%'`
- Render: `NSTextField` overlay, `NSColor.tertiaryLabelColor`
- Accept: `→` or `Tab`
- Dismiss: `Escape` or after Backspace

### Tab Completion Popup
- `$PATH` cached on launch (200 ms budget)
- `$PWD` listing live each trigger
- Single match → inline insert
- Multi-match → `NSTableView` popup; arrows + Enter/Tab/Esc

### Ctrl+R Fuzzy Search
- Floating `NSSearchField` above active line
- Substring match, case-insensitive
- Top 8 results sorted by recency
- `Enter` → paste into current line (no auto-execute)

### Dedup Rules
- Skip consecutive duplicate
- Skip leading-space commands
- Skip comment-only inputs

---

## 8. Native macOS UI

| Element | Implementation |
|---|---|
| Window chrome | `.titleBar` + `.unified` |
| Tabs | `NSWindowTabbing` |
| Sidebar | `NavigationSplitView` |
| Split panes | `NSSplitView` |
| Dark/light | `@Environment(\.colorScheme)` |
| Accent | `NSColor.controlAccentColor` |
| Settings | SwiftUI `Settings { }` scene |

Keybindings per PRD §11.

---

## 9. Themes

5 built-in JSON themes in `Themes/builtin/`. Custom = drag JSON into Settings. Schema:

```json
{
  "name": "Tokyo Night",
  "background": "#1a1b26",
  "foreground": "#a9b1d6",
  "cursor": "#c0caf5",
  "ansi": ["#15161e","#f7768e","#9ece6a","#e0af68","#7aa2f7","#bb9af7","#7dcfff","#a9b1d6",
           "#414868","#f7768e","#9ece6a","#e0af68","#7aa2f7","#bb9af7","#7dcfff","#c0caf5"]
}
```

---

## 10. Dependencies (SPM)

| Package | URL | Version |
|---|---|---|
| SwiftTerm | `https://github.com/migueldeicaza/SwiftTerm` | from: 1.2.0 |
| GRDB.swift | `https://github.com/groue/GRDB.swift` | from: 6.0.0 |

---

## 11. Testing Strategy

| Layer | Test type | Tool |
|---|---|---|
| `CommentFilter` | Unit (table-driven) | XCTest |
| `AutocompleteEngine` | Unit (mocked DB) | XCTest |
| `HistoryDatabase` | Integration (in-memory SQLite) | XCTest + GRDB `DatabaseQueue.inMemory()` |
| `TorTerminalView` | Snapshot via UI test | XCUITest |
| Window/tabs/split | UI test | XCUITest |

TDD applied to Input + History modules before SwiftTerm integration.

---

## 12. Performance Budgets

| Metric | Target |
|---|---|
| Cold launch | < 300 ms |
| Memory (1 tab idle) | < 80 MB |
| History search (10k rows) | < 50 ms |
| Ghost text suggest | < 10 ms |
| `$PATH` scan (cold) | < 200 ms |

Verified via Instruments (Time Profiler + Allocations).

---

## 13. Implementation Phases

| Phase | Weeks | Deliverable | Gate |
|---|---|---|---|
| 1 — Core Terminal | 1–2 | PTY + SwiftTerm + comment filter + native window/tabs | Manual smoke test |
| 2 — Autocomplete | 3–4 | GRDB history + ghost text + tab completion | Unit/integration tests green |
| 3 — Polish | 5–6 | Ctrl+R, split pane, themes, settings, menu bar | UI tests green |
| 4 — QA & Release | 7 | Notarization, profiling, README, DMG | Performance budgets met |

---

## 14. Out of Scope (v1)

SSH, AI suggestion, plugins, collaboration, iOS, Vim/tmux integration.

---

## 15. Open Risks

1. SwiftTerm `LocalProcessTerminalView.send()` override — confirm hook fires before VT processing. Mitigation: prototype day 1; fall back to Approach B.
2. Ghost text overlay alignment — char-cell positioning across font metrics. Mitigation: SwiftTerm `getCaretPosition()` if exposed; else `font.maximumAdvancement`.
3. GRDB version pin — major versions break API. Mitigation: lock 6.x in `Package.resolved`.

---

## 16. Success Criteria (v1)

- Cold launch < 300 ms on M1+
- 10k-command history with < 50 ms search
- CommentFilter table tests 100% pass
- 5 themes ship and switch live
- Notarized DMG via `notarytool`
- README + LICENSE in repo

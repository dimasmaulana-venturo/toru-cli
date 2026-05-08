import SwiftUI

struct TerminalSession: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var createdAt: Date = .init()
}

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [TerminalSession] = [
        TerminalSession(title: "Session 1")
    ]
    @Published var selectedID: UUID?

    init() { selectedID = sessions.first?.id }

    func newSession() {
        let s = TerminalSession(title: "Session \(sessions.count + 1)")
        sessions.append(s)
        selectedID = s.id
    }

    func close(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if selectedID == id { selectedID = sessions.first?.id }
    }
}

struct SidebarView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        List(selection: $store.selectedID) {
            Section("Sessions") {
                ForEach(store.sessions) { session in
                    HStack {
                        Image(systemName: "terminal")
                            .foregroundStyle(.tint)
                        Text(session.title)
                        Spacer()
                    }
                    .tag(session.id)
                    .contextMenu {
                        Button("Close", role: .destructive) {
                            store.close(session.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.newSession()
                } label: {
                    Label("New Session", systemImage: "plus")
                }
                .help("New session (⌘T)")
            }
        }
    }
}

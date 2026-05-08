import SwiftUI
import AppKit

/// Tab strip across the top of the active `Session`'s pane. Each tab is a
/// `TabState` (one shell). Click to switch active tab; "+" appends a new
/// tab to the current session.
struct TabBarView: View {
    @ObservedObject var session: Session

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(session.tabs) { tab in
                        TabChip(
                            tab: tab,
                            isActive: tab.id == session.selectedTabID,
                            canClose: session.tabs.count > 1,
                            onSelect: {
                                DispatchQueue.main.async {
                                    session.selectedTabID = tab.id
                                }
                            },
                            onClose: { session.closeTab(tab.id) }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            Button {
                session.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(.plain)
            .help("New tab (⌘T)")
            .keyboardShortcut("t", modifiers: [.command])
            .padding(.trailing, 6)
        }
        .frame(height: 32)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }
}

private struct TabChip: View {
    @ObservedObject var tab: TabState
    let isActive: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 10))
                .foregroundStyle(isActive ? Color.teal : Color.secondary)
            Text(tab.title)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .lineLimit(1)
            if canClose && (hovering || isActive) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close tab")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isActive
                      ? Color.white.opacity(0.10)
                      : (hovering ? Color.white.opacity(0.04) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onSelect() }
    }
}

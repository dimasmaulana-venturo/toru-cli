import SwiftUI
import AppKit

/// Finder-style tab strip rendered below the window toolbar when the
/// active session has 2+ tabs. Each tab takes equal width, has a close
/// `×` on the left (visible on hover or when active), and the active
/// tab is highlighted while inactive tabs are separated by hairline
/// vertical dividers.
struct TabStripView: View {
    @ObservedObject var session: Session

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(session.tabs.enumerated()), id: \.element.id) { idx, tab in
                FinderTab(
                    tab: tab,
                    isActive: tab.id == session.selectedTabID,
                    showLeadingDivider: shouldShowLeadingDivider(at: idx),
                    onSelect: {
                        DispatchQueue.main.async {
                            session.selectedTabID = tab.id
                        }
                    },
                    onClose: { session.closeTab(tab.id) }
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    /// Show a divider on the leading edge of a tab when neither it nor
    /// its left neighbor is the active tab — matches Finder's behavior.
    private func shouldShowLeadingDivider(at idx: Int) -> Bool {
        guard idx > 0 else { return false }
        let cur = session.tabs[idx]
        let prev = session.tabs[idx - 1]
        return cur.id != session.selectedTabID && prev.id != session.selectedTabID
    }
}

private struct FinderTab: View {
    @ObservedObject var tab: TabState
    let isActive: Bool
    let showLeadingDivider: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false

    var body: some View {
        ZStack {
            // Background fill (active tab lighter).
            Rectangle()
                .fill(isActive
                      ? Color.white.opacity(0.08)
                      : (hovering ? Color.white.opacity(0.03) : Color.clear))

            // Centered title; close button overlays at leading edge.
            HStack {
                Spacer()
                Text(tab.title)
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 28)

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(hovering ? 0.10 : 0))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity((hovering || isActive) ? 1 : 0)
                .padding(.leading, 8)
                .help("Close tab")
                Spacer()
            }
        }
        .overlay(alignment: .leading) {
            if showLeadingDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)
                    .padding(.vertical, 6)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onSelect() }
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .animation(.easeInOut(duration: 0.12), value: isActive)
    }
}

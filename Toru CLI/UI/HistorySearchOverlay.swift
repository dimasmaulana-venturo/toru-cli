import SwiftUI

struct HistorySearchOverlay: View {
    @Binding var isPresented: Bool
    @State private var query: String = ""
    @State private var results: [CommandHistory] = []
    var onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search history…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: query) { _, q in refresh(q) }
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            Divider()
            List(results) { r in
                HStack {
                    Image(systemName: "arrow.uturn.left")
                        .foregroundStyle(.tertiary)
                    Text(r.command)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Text(r.executedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(r.command)
                    isPresented = false
                }
            }
            .frame(maxHeight: 240)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        .frame(width: 520)
        .padding()
    }

    private func refresh(_ q: String) {
        results = HistoryDatabase.shared.search(query: q, limit: 8)
    }
}

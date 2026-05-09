import SwiftUI

/// Vertical scroll of `Block` cards, bottom-anchored. Auto-scrolls to the
/// newest block whenever:
///   - a new block is appended (count changes), or
///   - the running block keeps streaming bytes (last block's output grows).
struct BlockListView: View {
    @ObservedObject var blockStore: BlockStore
    var isLocked: Bool = false
    var searchQuery: String = ""
    /// When false, omit blocks whose `isRunning` is still true. Used so the
    /// in-progress block lives only in the bottom `ActiveCellView` and
    /// doesn't render twice.
    var showRunning: Bool = true
    var onRerun: ((Block) -> Void)? = nil
    var onDelete: ((Block) -> Void)? = nil

    private var visibleBlocks: [Block] {
        var arr = blockStore.blocks
        if !showRunning { arr = arr.filter { !$0.isRunning } }
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return arr }
        return arr.filter { block in
            block.command.lowercased().contains(q) ||
            String(block.output.characters).lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(visibleBlocks) { block in
                        BlockRowView(
                            block: block,
                            isLocked: isLocked,
                            searchQuery: searchQuery,
                            onRerun: onRerun,
                            onDelete: onDelete
                        )
                        .id(block.id)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.spring(response: 0.32, dampingFraction: 0.86),
                           value: visibleBlocks.map(\.id))
            }
            .frame(maxWidth: .infinity)
            .defaultScrollAnchor(.bottom)
            .onChange(of: blockStore.blocks.count) {
                guard let last = blockStore.blocks.last else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: blockStore.streamTick) {
                guard let last = blockStore.blocks.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

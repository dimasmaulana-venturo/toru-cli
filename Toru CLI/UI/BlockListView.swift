import SwiftUI

/// Vertical scroll of `Block` cards, bottom-anchored. Auto-scrolls to the
/// newest block whenever:
///   - a new block is appended (count changes), or
///   - the running block keeps streaming bytes (last block's output grows).
struct BlockListView: View {
    @ObservedObject var blockStore: BlockStore
    var isLocked: Bool = false
    var searchQuery: String = ""
    var onRerun: ((Block) -> Void)? = nil
    var onDelete: ((Block) -> Void)? = nil

    private var visibleBlocks: [Block] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return blockStore.blocks }
        return blockStore.blocks.filter { block in
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
                            onRerun: onRerun,
                            onDelete: onDelete
                        )
                        .id(block.id)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
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

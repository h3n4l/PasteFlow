import SwiftUI

struct ClipListView: View {
    @ObservedObject var appState: AppState
    var onItemActivate: ((ClipboardItem) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewport = Viewport()

    /// Breathing room above the first row and below the last.
    private static let edgeGap: CGFloat = 4
    private static let scrollSpace = "clipList"

    var body: some View {
        let items = appState.filteredItems
        let selectedIndex = items.firstIndex { $0.id == appState.selectedItem?.id }
        // The highlight glides only to a row that is already in view. Reaching any other row
        // scrolls the list, which happens at once, so the highlight has to jump along with it.
        let glides = selectedIndex.map { viewport.shows(rowAt: $0, of: items.count) } ?? false
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipRowView(
                            item: item,
                            isSelected: appState.selectedItem?.id == item.id,
                            isPasting: appState.pastingItemID == item.id,
                            shortcutIndex: index
                        ) {
                            if appState.selectedItem?.id == item.id {
                                onItemActivate?(item)
                            } else {
                                appState.select(item)
                            }
                        }
                        // The gaps sit inside the id so that scrolling to the first or last row reveals them as well.
                        .padding(.top, index == 0 ? Self.edgeGap : 0)
                        .padding(.bottom, index == items.count - 1 ? Self.edgeGap : 0)
                        .id(item.id)
                        .transition(PanelMotion.rowTransition(reduceMotion: reduceMotion))
                        .onAppear {
                            if index == items.count - 5 { appState.loadMoreItems() }
                        }
                    }
                }
                .background(alignment: .top) {
                    selectionHighlight(at: selectedIndex, glides: glides)
                }
                .background(GeometryReader { content in
                    Color.clear.preference(key: ContentTopKey.self, value: content.frame(in: .named(Self.scrollSpace)).minY)
                })
                // Rows slide to their new places when the list changes. The highlight is inside this
                // too, so when the selected row moves, the highlight travels with it.
                .panelAnimation(PanelMotion.listChange, value: appState.listChanges)
                .panelAnimation(PanelMotion.selectionTint, value: appState.selectionMoves)
            }
            .coordinateSpace(name: Self.scrollSpace)
            .background(GeometryReader { list in
                Color.clear.preference(key: ListHeightKey.self, value: list.size.height)
            })
            .onPreferenceChange(ContentTopKey.self) { if let top = $0 { viewport.contentTop = top } }
            .onPreferenceChange(ListHeightKey.self) { if let height = $0 { viewport.height = height } }
            .onChange(of: appState.selectedItem?.id) { id in
                if let id {
                    // Scrolling is not animated: an animated scroll did not move the list at all on macOS 27.
                    withAnimation(.none) {
                        proxy.scrollTo(id, anchor: nil)
                    }
                }
            }
        }
        .frame(width: 340)
        .overlay(Rectangle().frame(width: 1).foregroundColor(Color(.borderDivider)), alignment: .trailing)
    }

    /// The one highlight behind the selected row. Rows are all the same height, so its place
    /// follows from the row's number, and it can glide between rows that are not loaded yet.
    @ViewBuilder
    private func selectionHighlight(at index: Int?, glides: Bool) -> some View {
        if let index {
            RoundedRectangle(cornerRadius: PanelSkin.selectionCornerRadius)
                .fill(Color(.backgroundSelected))
                .frame(height: ClipRowView.height)
                .padding(.horizontal, ClipRowView.highlightInset)
                .offset(y: Self.edgeGap + CGFloat(index) * ClipRowView.height)
                // Without a glide this clears any animation set further out, so the highlight jumps.
                .panelAnimation(glides ? PanelMotion.selection : nil, value: appState.selectionMoves)
        }
    }

    /// Where the list's rows are within the scroll view, kept up to date as the list scrolls.
    /// A class, so that scrolling does not redraw the list.
    private final class Viewport {
        /// The top of the rows, measured from the top of the list's visible area. Negative once the list has scrolled.
        var contentTop: CGFloat = 0
        /// The height of the list's visible area, which starts below the bar above the list.
        var height: CGFloat = 0

        /// Whether a row is in view in full, including the gap beyond it if it is the first or last.
        func shows(rowAt index: Int, of count: Int) -> Bool {
            var top = contentTop + ClipListView.edgeGap + CGFloat(index) * ClipRowView.height
            var bottom = top + ClipRowView.height
            if index == 0 { top -= ClipListView.edgeGap }
            if index == count - 1 { bottom += ClipListView.edgeGap }
            // Half a point of slack for rounding in the scroll position.
            return top >= -0.5 && bottom <= height + 0.5
        }
    }
}

// Both keys keep the one value that was reported; views that report nothing must not replace it.

private struct ContentTopKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = value ?? nextValue() }
}

private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = value ?? nextValue() }
}

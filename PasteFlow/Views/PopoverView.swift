import SwiftUI

struct PopoverView: View {
    @ObservedObject var appState: AppState
    @FocusState private var isSearchFocused: Bool
    /// Pastes an item and closes the panel.
    var onPaste: (ClipboardItem) -> Void

    var body: some View {
        // No background here: FloatingPanel provides the translucent material behind this view.
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ClipListView(appState: appState, onItemActivate: onPaste)
                DetailPanelView(
                    item: appState.selectedItem,
                    changeCount: appState.selectionMoves + appState.listChanges,
                    onPaste: onPaste,
                    onDelete: { item in appState.deleteItem(item) },
                    onCopyPath: { item in appState.copyPathItem(item) }
                ).frame(width: 220)
            }
            .frame(maxHeight: .infinity)
            .panelTopBar {
                SearchBarView(searchText: $appState.searchText, isSearchFocused: $isSearchFocused)
                FilterRowView(activeFilter: Binding(
                    get: { appState.activeFilter },
                    set: { appState.setFilter($0) }
                ))
            }
            FooterView(
                itemCount: appState.totalItemCount,
                listChanges: appState.listChanges,
                statusMessage: appState.statusMessage,
                isAccessibilityGranted: appState.isAccessibilityGranted
            )
        }
        .frame(width: 560, height: 456)
        .onChange(of: appState.isPanelVisible) { visible in
            if visible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
            }
        }
    }
}

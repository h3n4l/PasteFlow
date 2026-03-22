import SwiftUI

struct PopoverView: View {
    @ObservedObject var appState: AppState
    @FocusState private var isSearchFocused: Bool
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SearchBarView(searchText: $appState.searchText, isSearchFocused: $isSearchFocused)
            FilterRowView(activeFilter: Binding(
                get: { appState.activeFilter },
                set: { appState.setFilter($0) }
            ))
            HStack(spacing: 0) {
                ClipListView(appState: appState, onItemActivate: { item in pasteAndDismiss(item) })
                DetailPanelView(
                    item: appState.selectedItem,
                    onPaste: { item in pasteAndDismiss(item) },
                    onDelete: { item in appState.deleteItem(item) },
                    onCopyPath: { item in appState.copyPathItem(item) }
                ).frame(width: 220)
            }.frame(maxHeight: .infinity)
            FooterView(
                itemCount: appState.totalItemCount,
                statusMessage: appState.statusMessage,
                isAccessibilityGranted: appState.isAccessibilityGranted
            )
        }
        .frame(width: 560, height: 456)
        .background(Color(.backgroundPrimary))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.borderDivider), lineWidth: 1))
        .onChange(of: appState.isPanelVisible) { visible in
            if visible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
            }
        }
    }

    private func pasteAndDismiss(_ item: ClipboardItem) {
        onDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { appState.pasteItem(item) }
    }
}

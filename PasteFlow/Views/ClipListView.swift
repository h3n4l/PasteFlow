import SwiftUI

struct ClipListView: View {
    @ObservedObject var appState: AppState
    var onItemActivate: ((ClipboardItem) -> Void)?
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(appState.filteredItems.enumerated()), id: \.element.id) { index, item in
                        ClipRowView(item: item, isSelected: appState.selectedItem?.id == item.id, shortcutIndex: index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if appState.selectedItem?.id == item.id {
                                    onItemActivate?(item)
                                } else {
                                    appState.selectedItem = item
                                }
                            }
                            // Breathing room above the first row and below the last. It sits inside
                            // the id so that scrolling to either row reveals the gap as well.
                            .padding(.top, index == 0 ? 4 : 0)
                            .padding(.bottom, index == appState.filteredItems.count - 1 ? 4 : 0)
                            .id(item.id)
                            .onAppear {
                                if index == appState.filteredItems.count - 5 { appState.loadMoreItems() }
                            }
                    }
                }
            }
            .onChange(of: appState.selectedItem?.id) { _ in
                if let id = appState.selectedItem?.id {
                    withAnimation(.none) {
                        proxy.scrollTo(id, anchor: nil)
                    }
                }
            }
        }
        .frame(width: 340)
        .overlay(Rectangle().frame(width: 1).foregroundColor(Color(.borderDivider)), alignment: .trailing)
    }
}

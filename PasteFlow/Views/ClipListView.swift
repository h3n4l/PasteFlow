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
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if appState.selectedItem?.id == item.id {
                                    onItemActivate?(item)
                                } else {
                                    appState.selectedItem = item
                                }
                            }
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
        .frame(width: 340).background(Color.white)
        .overlay(Rectangle().frame(width: 1).foregroundColor(Color(hex: 0xE5E5E5)), alignment: .trailing)
    }
}

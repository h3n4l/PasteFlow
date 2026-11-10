import SwiftUI

struct SearchBarView: View {
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color(.textSecondary))
                .font(.system(size: 14))
            TextField("Search clipboard...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(isSearchFocused)
            Spacer()
            HStack(spacing: 2) {
                KeyCapHint(key: "⌘")
                KeyCapHint(key: "⇧")
                KeyCapHint(key: "V")
            }
        }
        .panelSearchFieldChrome()
    }
}

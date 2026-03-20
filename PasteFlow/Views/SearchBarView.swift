import SwiftUI

struct SearchBarView: View {
    @Binding var searchText: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color(hex: 0x999999))
                .font(.system(size: 14))
            TextField("Search clipboard...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            Spacer()
            Text("Cmd+Shift+V")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: 0x999999))
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color.white)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(hex: 0xE5E5E5)), alignment: .bottom)
    }
}

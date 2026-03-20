import SwiftUI

struct FilterRowView: View {
    @Binding var activeFilter: ContentType?
    private let filters: [(label: String, type: ContentType?)] = [
        ("All", nil), ("Text", .text), ("Link", .link), ("Code", .code), ("Image", .image),
    ]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(filters, id: \.label) { filter in
                FilterPill(label: filter.label, isActive: activeFilter == filter.type) {
                    activeFilter = filter.type
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6).frame(height: 32)
        .background(Color.white)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(hex: 0xE5E5E5)), alignment: .bottom)
    }
}

private struct FilterPill: View {
    let label: String
    let isActive: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 11)).foregroundColor(Color(hex: 0x3C3489))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(isActive ? Color(hex: 0xEEEDFE) : Color.clear)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(hex: 0xCECBF6), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

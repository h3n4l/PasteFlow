import SwiftUI

struct FilterRowView: View {
    @Binding var activeFilter: ContentType?
    private let filters: [(label: String, type: ContentType?)] = [
        ("All", nil), ("Text", .text), ("Link", .link), ("Code", .code), ("Image", .image), ("File", .file),
    ]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(filters, id: \.label) { filter in
                FilterPill(label: filter.label, isActive: activeFilter == filter.type) {
                    activeFilter = filter.type
                }
            }
            Spacer()
            KeyCapHint(key: "Tab", label: "Filter")
        }
        .padding(.horizontal, 12).padding(.vertical, 6).frame(height: 32)
        .background(Color(.backgroundPrimary))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(.borderDivider)), alignment: .bottom)
    }
}

private struct FilterPill: View {
    let label: String
    let isActive: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 11)).foregroundColor(Color(.accentPurple))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(isActive ? Color(.backgroundPill) : Color.clear)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(.borderPill), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

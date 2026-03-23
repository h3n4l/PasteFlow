import SwiftUI

struct FooterView: View {
    let itemCount: Int
    let statusMessage: String?
    let isAccessibilityGranted: Bool
    var body: some View {
        HStack {
            if let message = statusMessage {
                Text(message).font(.system(size: 11)).foregroundColor(.red.opacity(0.7))
            } else if !isAccessibilityGranted {
                Text("Accessibility: off \u{2014} manual paste mode")
                    .font(.system(size: 11)).foregroundColor(Color(.textSecondary))
            } else {
                HStack(spacing: 10) {
                    KeyCapHint(key: "↑", label: nil)
                    KeyCapHint(key: "↓", label: "Navigate")
                    KeyCapHint(key: "Enter", label: "Paste")
                    KeyCapHint(key: "⌘1-9", label: "Quick paste")
                }
            }
            Spacer()
            Text("\(itemCount) items").font(.system(size: 11)).foregroundColor(Color(.textSecondary))
        }
        .padding(.horizontal, 12).padding(.vertical, 7).frame(height: 27)
        .background(Color(.backgroundPrimary))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(.borderDivider)), alignment: .top)
    }

}

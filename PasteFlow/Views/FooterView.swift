import SwiftUI

struct FooterView: View {
    let itemCount: Int
    /// Changes whenever the list changed in a way the panel animates, which is when the count rolls.
    let listChanges: Int
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
            countText.font(.system(size: 11)).foregroundColor(Color(.textSecondary))
                .panelAnimation(PanelMotion.listChange, value: listChanges)
        }
        .padding(.horizontal, 12).padding(.vertical, 7).frame(height: 27)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(.borderDivider)), alignment: .top)
    }

    /// The item count, whose digits roll when it changes.
    @ViewBuilder
    private var countText: some View {
        let text = Text("\(itemCount) items").monospacedDigit()
        if #available(macOS 14.0, *) {
            // Rolls up or down according to which way the count went.
            text.contentTransition(.numericText(value: Double(itemCount)))
        } else {
            text.contentTransition(.numericText())
        }
    }

}

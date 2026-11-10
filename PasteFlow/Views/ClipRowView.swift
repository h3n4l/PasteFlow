import SwiftUI

struct ClipRowView: View {
    /// Every row is this tall, which is what lets the list place the selection highlight by row number.
    static let height: CGFloat = 44
    /// How far the selection highlight is inset from the list's edges.
    static let highlightInset: CGFloat = 6

    let item: ClipboardItem
    let isSelected: Bool
    /// Whether this row is the one being pasted, which lights it up.
    let isPasting: Bool
    let shortcutIndex: Int?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? Color(.accentBlue) : Color(.textSecondary))
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(previewText)
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? Color(.accentBlue) : Color(.textPrimary))
                        .lineLimit(1).truncationMode(.tail)
                    Text(metadataText)
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? Color(.accentBlue).opacity(0.6) : Color(.textSecondary))
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let index = shortcutIndex, index < 9 {
                    KeyCapHint(key: "⌘\(index + 1)")
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 7).frame(height: Self.height)
        }
        .buttonStyle(RowButtonStyle(isHovered: isHovered, isPasting: isPasting))
        .onHover { isHovered = $0 }
        // The row content stays 12pt from the list edge; its tint lines up with the selection highlight.
        .padding(.horizontal, Self.highlightInset)
    }

    private var iconName: String {
        switch item.contentType {
        case .text: return "textformat"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc.on.doc"
        }
    }

    private var previewText: String {
        switch item.content {
        case .text(let text):
            return text.replacingOccurrences(of: "\n", with: " ")
        case .image(_, let format):
            if let name = item.sourceFilename { return name }
            return "\(format.rawValue.uppercased()) image"
        case .file(let refs):
            if refs.count == 1 { return refs[0].name }
            return "\(refs.count) files"
        }
    }

    private var metadataText: String {
        let timeAgo = item.createdAt.relativeString()
        switch item.content {
        case .text(let text):
            if item.contentType == .link, let host = URL(string: text)?.host {
                return "\(timeAgo) \u{00B7} \(host)"
            }
            return "\(timeAgo) \u{00B7} \(item.characterCount ?? text.count) chars"
        case .image(let data, let format):
            return "\(timeAgo) \u{00B7} \(format.rawValue.uppercased()) image \u{00B7} \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
        case .file(let refs):
            if refs.count == 1 {
                return "\(timeAgo) \u{00B7} \(refs[0].utiDescription) \u{00B7} \(ByteCountFormatter.string(fromByteCount: refs[0].size, countStyle: .file))"
            }
            let totalSize = refs.reduce(Int64(0)) { $0 + $1.size }
            return "\(timeAgo) \u{00B7} \(refs.count) files \u{00B7} \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)) total"
        }
    }
}

/// A row's reaction to the pointer and to being pasted. The selection highlight is not drawn
/// here: the list draws one highlight and moves it from row to row.
private struct RowButtonStyle: ButtonStyle {
    let isHovered: Bool
    let isPasting: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .panelPressScale(PanelMotion.rowPressScale, isPressed: configuration.isPressed)
            .background(
                RoundedRectangle(cornerRadius: PanelSkin.selectionCornerRadius)
                    .fill(Color(.textPrimary).opacity(isHovered ? 0.06 : 0))
                    .animation(PanelMotion.hover, value: isHovered)
            )
            .background(
                RoundedRectangle(cornerRadius: PanelSkin.selectionCornerRadius)
                    .fill(Color(.backgroundPasteFlash).opacity(isPasting ? 1 : 0))
                    .animation(PanelMotion.pasteFlash, value: isPasting)
            )
            // The whole row is clickable, not just its text.
            .contentShape(Rectangle())
    }
}

import SwiftUI

struct ClipRowView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let shortcutIndex: Int?

    var body: some View {
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
                Text("Cmd+\(index + 1)")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? Color(.accentBlue).opacity(0.5) : Color(.textSecondary))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7).frame(height: 44)
        .background(isSelected ? Color(.backgroundSelected) : Color(.backgroundPrimary))
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

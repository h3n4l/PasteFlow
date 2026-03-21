import SwiftUI

struct ClipRowView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let shortcutIndex: Int?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? Color(hex: 0x185FA5) : Color(hex: 0x999999))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(previewText)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? Color(hex: 0x185FA5) : Color(hex: 0x1A1A1A))
                    .lineLimit(1).truncationMode(.tail)
                Text(metadataText)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? Color(hex: 0x185FA5).opacity(0.6) : Color(hex: 0x999999))
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let index = shortcutIndex, index < 9 {
                Text("Cmd+\(index + 1)")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? Color(hex: 0x185FA5).opacity(0.5) : Color(hex: 0x999999))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7).frame(height: 44)
        .background(isSelected ? Color(hex: 0xE6F1FB) : Color.white)
    }

    private var iconName: String {
        switch item.contentType {
        case .text: return "textformat"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .link: return "link"
        case .image: return "photo"
        }
    }

    private var previewText: String {
        switch item.content {
        case .text(let text): return text.replacingOccurrences(of: "\n", with: " ")
        case .image(_, let format): return "Image (\(format.rawValue.uppercased()))"
        }
    }

    private var metadataText: String {
        let timeAgo = item.createdAt.relativeString()
        switch item.content {
        case .text(let text):
            if item.contentType == .link, let host = URL(string: text)?.host {
                return "\(timeAgo) \u{00B7} \(host)"
            }
            return "\(timeAgo) \u{00B7} \(text.count) chars"
        case .image(let data, _):
            return "\(timeAgo) \u{00B7} \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
        }
    }
}


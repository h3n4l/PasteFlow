import SwiftUI

struct DetailPanelView: View {
    let item: ClipboardItem?
    let onPaste: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void
    let onCopyPath: ((ClipboardItem) -> Void)?

    var body: some View {
        if let item = item {
            VStack(alignment: .leading, spacing: 10) {
                Text("Preview")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(.textTertiary))
                // The preview gets first claim on the pane's height; the actions stay at the bottom.
                previewBlock(for: item)
                    .layoutPriority(1)
                metadataSection(for: item)
                Spacer(minLength: 0)
                actionButtons(for: item)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack {
                Spacer()
                Text("No item selected")
                    .font(.system(size: 13))
                    .foregroundColor(Color(.textSecondary))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func previewBlock(for item: ClipboardItem) -> some View {
        switch item.content {
        case .text(let text):
            let displayText = (item.characterCount ?? 0) > 2500 ? String(text.prefix(2500)) + "…" : text
            fittedPreview {
                Text(displayText)
                    .font(.system(size: 11, design: item.contentType == .code ? .monospaced : .default))
                    .foregroundColor(Color(.textTertiary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        case .image(let data, _):
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 120)
                    .cornerRadius(8)
            }
        case .file(let refs):
            fittedPreview {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(refs, id: \.path) { ref in
                        HStack(spacing: 6) {
                            Image(systemName: "doc")
                                .font(.system(size: 11))
                                .foregroundColor(Color(.textSecondary))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ref.name)
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(.textTertiary))
                                Text("\(ref.utiDescription) \u{00B7} \(ByteCountFormatter.string(fromByteCount: ref.size, countStyle: .file))")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(.textSecondary))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
    }

    /// A preview block as tall as its content, which scrolls only when the content
    /// is taller than the space the pane can give it.
    private func fittedPreview<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let content = content()
        return ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .background(Color(.backgroundPreview))
        .cornerRadius(8)
    }

    private func metadataSection(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch item.content {
            case .text:
                Text("\(item.contentType.rawValue.capitalized) \u{00B7} \(item.characterCount ?? 0) characters")
                    .font(.system(size: 11)).foregroundColor(Color(.textSecondary))
            case .image(let data, let format):
                Text("\(format.rawValue.uppercased()) \u{00B7} \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
                    .font(.system(size: 11)).foregroundColor(Color(.textSecondary))
            case .file(let refs):
                if refs.count == 1 {
                    Text("\(refs[0].utiDescription) \u{00B7} \(ByteCountFormatter.string(fromByteCount: refs[0].size, countStyle: .file))")
                        .font(.system(size: 11)).foregroundColor(Color(.textSecondary))
                } else {
                    let totalSize = refs.reduce(Int64(0)) { $0 + $1.size }
                    Text("\(refs.count) files \u{00B7} \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)) total")
                        .font(.system(size: 11)).foregroundColor(Color(.textSecondary))
                }
            }
            Text("Copied \(item.createdAt.relativeString())")
                .font(.system(size: 11)).foregroundColor(Color(.textSecondary))
            if let sourceApp = item.sourceApp {
                Text("Source: \(sourceApp)")
                    .font(.system(size: 11)).foregroundColor(Color(.textSecondary))
            }
        }
    }

    private func actionButtons(for item: ClipboardItem) -> some View {
        HStack(spacing: 6) {
            Button("Paste") { onPaste(item) }
                .buttonStyle(PanelActionButtonStyle(kind: .primary))
            if case .file = item.content {
                Button("Copy Path") { onCopyPath?(item) }
                    .buttonStyle(PanelActionButtonStyle(kind: .secondary))
            }
            Button("Delete") { onDelete(item) }
                .buttonStyle(PanelActionButtonStyle())
        }
    }
}

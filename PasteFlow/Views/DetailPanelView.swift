import SwiftUI

struct DetailPanelView: View {
    let item: ClipboardItem?
    let onPaste: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void
    let onCopyPath: ((ClipboardItem) -> Void)?

    var body: some View {
        if let item = item {
            VStack(alignment: .leading, spacing: 10) {
                Text("PREVIEW")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: 0x666666))
                    .tracking(0.5)
                previewBlock(for: item)
                metadataSection(for: item)
                actionButtons(for: item)
                Spacer()
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack {
                Spacer()
                Text("No item selected")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0x999999))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func previewBlock(for item: ClipboardItem) -> some View {
        switch item.content {
        case .text(let text):
            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: item.contentType == .code ? .monospaced : .default))
                    .foregroundColor(Color(hex: 0x666666))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 120)
            .background(Color(hex: 0xF5F5F3))
            .cornerRadius(8)
        case .image(let data, _):
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 120)
                    .cornerRadius(8)
            }
        case .file(let refs):
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(refs, id: \.path) { ref in
                        HStack(spacing: 6) {
                            Image(systemName: "doc")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: 0x999999))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ref.name)
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: 0x666666))
                                Text("\(ref.utiDescription) \u{00B7} \(ByteCountFormatter.string(fromByteCount: ref.size, countStyle: .file))")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: 0x999999))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(maxHeight: 120)
            .background(Color(hex: 0xF5F5F3))
            .cornerRadius(8)
        }
    }

    private func metadataSection(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch item.content {
            case .text(let text):
                Text("\(item.contentType.rawValue.capitalized) \u{00B7} \(text.count) characters")
                    .font(.system(size: 11)).foregroundColor(Color(hex: 0x999999))
            case .image(let data, let format):
                Text("\(format.rawValue.uppercased()) \u{00B7} \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
                    .font(.system(size: 11)).foregroundColor(Color(hex: 0x999999))
            case .file(let refs):
                if refs.count == 1 {
                    Text("\(refs[0].utiDescription) \u{00B7} \(ByteCountFormatter.string(fromByteCount: refs[0].size, countStyle: .file))")
                        .font(.system(size: 11)).foregroundColor(Color(hex: 0x999999))
                } else {
                    let totalSize = refs.reduce(Int64(0)) { $0 + $1.size }
                    Text("\(refs.count) files \u{00B7} \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)) total")
                        .font(.system(size: 11)).foregroundColor(Color(hex: 0x999999))
                }
            }
            Text("Copied \(item.createdAt.relativeString())")
                .font(.system(size: 11)).foregroundColor(Color(hex: 0x999999))
            if let sourceApp = item.sourceApp {
                Text("Source: \(sourceApp)")
                    .font(.system(size: 11)).foregroundColor(Color(hex: 0x999999))
            }
        }
    }

    private func actionButtons(for item: ClipboardItem) -> some View {
        HStack(spacing: 6) {
            Button(action: { onPaste(item) }) {
                Text("Paste").font(.system(size: 11)).foregroundColor(Color(hex: 0x3C3489))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color(hex: 0xEEEDFE)).cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xE5E5E5), lineWidth: 1))
            }.buttonStyle(.plain)
            if case .file = item.content {
                Button(action: { onCopyPath?(item) }) {
                    Text("Copy Path").font(.system(size: 11)).foregroundColor(Color(hex: 0x3C3489))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color(hex: 0xEEEDFE)).cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xE5E5E5), lineWidth: 1))
                }.buttonStyle(.plain)
            }
            Button(action: { onDelete(item) }) {
                Text("Delete").font(.system(size: 11)).foregroundColor(Color(hex: 0x3C3489))
                    .padding(.horizontal, 10).padding(.vertical, 4).cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xE5E5E5), lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }
}

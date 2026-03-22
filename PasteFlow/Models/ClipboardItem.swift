import Foundation
import CryptoKit

struct FileReference: Codable, Equatable {
    let path: String
    let name: String
    let size: Int64
    let utiType: String
    let utiDescription: String
}

enum ClipboardContent {
    case text(String)
    case image(Data, ImageFormat)
    case file([FileReference])
}

struct ClipboardItem: Identifiable {
    let id: UUID
    let content: ClipboardContent
    let sourceApp: String?
    let createdAt: Date
    let contentType: ContentType
    let characterCount: Int?
    let imageSize: Int?
    let contentHash: String

    init(id: UUID = UUID(), content: ClipboardContent, sourceApp: String?, createdAt: Date = Date(), contentType: ContentType) {
        self.id = id
        self.content = content
        self.sourceApp = sourceApp
        self.createdAt = createdAt
        self.contentType = contentType

        switch content {
        case .text(let text):
            self.characterCount = text.count
            self.imageSize = nil
            let hash = SHA256.hash(data: Data(text.utf8))
            self.contentHash = hash.map { String(format: "%02x", $0) }.joined()
        case .image(let data, _):
            self.characterCount = nil
            self.imageSize = data.count
            let hash = SHA256.hash(data: data)
            self.contentHash = hash.map { String(format: "%02x", $0) }.joined()
        case .file(let refs):
            self.characterCount = nil
            self.imageSize = nil
            let joined = refs.map(\.path).sorted().joined(separator: "\n")
            let hash = SHA256.hash(data: Data(joined.utf8))
            self.contentHash = hash.map { String(format: "%02x", $0) }.joined()
        }
    }

    internal init(id: UUID, content: ClipboardContent, sourceApp: String?,
                  createdAt: Date, contentType: ContentType,
                  characterCount: Int?, imageSize: Int?, contentHash: String) {
        self.id = id
        self.content = content
        self.sourceApp = sourceApp
        self.createdAt = createdAt
        self.contentType = contentType
        self.characterCount = characterCount
        self.imageSize = imageSize
        self.contentHash = contentHash
    }
}

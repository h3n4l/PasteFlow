import Foundation
import GRDB

struct ClipboardItemRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "clipboard_items"

    let id: String
    let contentType: String
    let textContent: String?
    let imagePath: String?
    let imageFormat: String?
    let sourceApp: String?
    let createdAt: Double
    let characterCount: Int?
    let imageSize: Int?
    let contentHash: String
    let sourceFilename: String?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let contentType = Column(CodingKeys.contentType)
        static let textContent = Column(CodingKeys.textContent)
        static let imagePath = Column(CodingKeys.imagePath)
        static let imageFormat = Column(CodingKeys.imageFormat)
        static let sourceApp = Column(CodingKeys.sourceApp)
        static let createdAt = Column(CodingKeys.createdAt)
        static let characterCount = Column(CodingKeys.characterCount)
        static let imageSize = Column(CodingKeys.imageSize)
        static let contentHash = Column(CodingKeys.contentHash)
        static let sourceFilename = Column(CodingKeys.sourceFilename)
    }
}

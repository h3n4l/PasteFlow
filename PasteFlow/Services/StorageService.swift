import Foundation
import GRDB
import os.log

final class StorageService {
    private let dbQueue: DatabaseQueue
    private let databasePath: String
    let imagesDirectory: URL
    private let logger = Logger(subsystem: "com.github.h3n4l.PasteFlow", category: "Storage")

    init(databasePath: String, imagesDirectory: URL) throws {
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        self.databasePath = databasePath
        self.imagesDirectory = imagesDirectory
        dbQueue = try DatabaseQueue(path: databasePath)

        try dbQueue.write { db in
            try db.create(table: ClipboardItemRecord.databaseTableName, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("contentType", .text).notNull()
                t.column("textContent", .text)
                t.column("imagePath", .text)
                t.column("imageFormat", .text)
                t.column("sourceApp", .text)
                t.column("createdAt", .double).notNull()
                t.column("characterCount", .integer)
                t.column("imageSize", .integer)
                t.column("contentHash", .text).notNull()
            }

            try db.create(index: "idx_content_hash", on: ClipboardItemRecord.databaseTableName,
                          columns: ["contentHash"], ifNotExists: true)
            try db.create(index: "idx_created_at", on: ClipboardItemRecord.databaseTableName,
                          columns: ["createdAt"], ifNotExists: true)
            try db.create(index: "idx_content_type", on: ClipboardItemRecord.databaseTableName,
                          columns: ["contentType"], ifNotExists: true)

            // Migration: add sourceFilename column
            if try !db.columns(in: ClipboardItemRecord.databaseTableName).contains(where: { $0.name == "sourceFilename" }) {
                try db.alter(table: ClipboardItemRecord.databaseTableName) { t in
                    t.add(column: "sourceFilename", .text)
                }
            }
        }
    }

    convenience init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let pasteFlowDir = appSupport.appendingPathComponent("PasteFlow")
        try FileManager.default.createDirectory(at: pasteFlowDir, withIntermediateDirectories: true)
        let dbPath = pasteFlowDir.appendingPathComponent("clipboard.db").path
        let imagesDir = pasteFlowDir.appendingPathComponent("images")
        try self.init(databasePath: dbPath, imagesDirectory: imagesDir)
    }

    func save(_ item: ClipboardItem) throws {
        var imagePath: String? = nil
        if case .image(let data, let format) = item.content {
            let filename = "\(item.id.uuidString).\(format.rawValue)"
            let fileURL = imagesDirectory.appendingPathComponent(filename)
            try data.write(to: fileURL)
            imagePath = filename
        }

        let textContent: String?
        switch item.content {
        case .text(let text):
            textContent = text
        case .file(let refs):
            textContent = String(data: try JSONEncoder().encode(refs), encoding: .utf8)
        case .image:
            textContent = nil
        }

        let record = ClipboardItemRecord(
            id: item.id.uuidString,
            contentType: item.contentType.rawValue,
            textContent: textContent,
            imagePath: imagePath,
            imageFormat: { if case .image(_, let format) = item.content { return format.rawValue }; return nil }(),
            sourceApp: item.sourceApp,
            createdAt: item.createdAt.timeIntervalSince1970,
            characterCount: item.characterCount,
            imageSize: item.imageSize,
            contentHash: item.contentHash,
            sourceFilename: item.sourceFilename
        )

        try dbQueue.write { db in
            // Deduplication: find duplicates FIRST (to get image paths), then delete
            let duplicates = try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.contentHash == item.contentHash)
                .fetchAll(db)

            for dup in duplicates {
                if let dupImagePath = dup.imagePath {
                    let fileURL = self.imagesDirectory.appendingPathComponent(dupImagePath)
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }

            try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.contentHash == item.contentHash)
                .deleteAll(db)

            try record.insert(db)
        }
    }

    func fetchItems(filter: ContentType?, search: String?, limit: Int, offset: Int) throws -> [ClipboardItem] {
        try dbQueue.read { db in
            var query = ClipboardItemRecord.all()

            if let filter = filter {
                query = query.filter(ClipboardItemRecord.Columns.contentType == filter.rawValue)
            }

            if let search = search, !search.isEmpty {
                let escaped = search
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                query = query.filter(ClipboardItemRecord.Columns.textContent.like("%\(escaped)%", escape: "\\"))
            }

            query = query.order(ClipboardItemRecord.Columns.createdAt.desc)
                .limit(limit, offset: offset)

            let records = try query.fetchAll(db)
            return records.map { self.recordToItem($0) }
        }
    }

    func delete(_ id: UUID) throws {
        try dbQueue.write { db in
            if let record = try ClipboardItemRecord.fetchOne(db, key: id.uuidString) {
                if let imagePath = record.imagePath {
                    let fileURL = self.imagesDirectory.appendingPathComponent(imagePath)
                    try? FileManager.default.removeItem(at: fileURL)
                }
                try record.delete(db)
            }
        }
    }

    func deleteExpired(olderThan days: Int) throws {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        try dbQueue.write { db in
            let expired = try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.createdAt < cutoff.timeIntervalSince1970)
                .fetchAll(db)
            for record in expired {
                if let imagePath = record.imagePath {
                    let fileURL = self.imagesDirectory.appendingPathComponent(imagePath)
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }

            try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.createdAt < cutoff.timeIntervalSince1970)
                .deleteAll(db)
        }
    }

    func itemCount(filter: ContentType?) throws -> Int {
        try dbQueue.read { db in
            var query = ClipboardItemRecord.all()
            if let filter = filter {
                query = query.filter(ClipboardItemRecord.Columns.contentType == filter.rawValue)
            }
            return try query.fetchCount(db)
        }
    }

    func loadImageData(for item: ClipboardItem) -> Data? {
        guard case .image(_, let format) = item.content else { return nil }
        let filename = "\(item.id.uuidString).\(format.rawValue)"
        let fileURL = imagesDirectory.appendingPathComponent(filename)
        return try? Data(contentsOf: fileURL)
    }

    /// Returns total data size in bytes (database + image files).
    func dataSize() -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default

        // Database file size
        if let attrs = try? fm.attributesOfItem(atPath: databasePath),
           let size = attrs[.size] as? Int64 {
            total += size
        }

        // Image files size
        if let enumerator = fm.enumerator(at: imagesDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }

        return total
    }

    // MARK: - Private

    private func recordToItem(_ record: ClipboardItemRecord) -> ClipboardItem {
        let content: ClipboardContent
        let contentType = ContentType(rawValue: record.contentType) ?? .text

        if contentType == .image,
           let imgPath = record.imagePath,
           let formatStr = record.imageFormat,
           let format = ImageFormat(rawValue: formatStr) {
            let fileURL = imagesDirectory.appendingPathComponent(imgPath)
            let data = (try? Data(contentsOf: fileURL)) ?? Data()
            content = .image(data, format)
        } else if contentType == .file,
                  let jsonStr = record.textContent,
                  let jsonData = jsonStr.data(using: .utf8),
                  let refs = try? JSONDecoder().decode([FileReference].self, from: jsonData) {
            content = .file(refs)
        } else {
            content = .text(record.textContent ?? "")
        }

        return ClipboardItem(
            id: UUID(uuidString: record.id) ?? UUID(),
            content: content,
            sourceApp: record.sourceApp,
            createdAt: Date(timeIntervalSince1970: record.createdAt),
            contentType: contentType,
            characterCount: record.characterCount,
            imageSize: record.imageSize,
            contentHash: record.contentHash,
            sourceFilename: record.sourceFilename
        )
    }
}

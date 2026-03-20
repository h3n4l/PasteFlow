# PasteFlow MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS clipboard history manager that monitors the clipboard, stores text and image history in SQLite, and lets users search and paste from history via a global hotkey.

**Architecture:** Menu bar app with no Dock icon. A centered NSPanel (AppKit) hosts all SwiftUI views. Central AppState (ObservableObject) drives the UI. GRDB handles SQLite persistence, images stored as files on disk. Clipboard monitoring via NSPasteboard polling, global hotkey via Carbon API, paste simulation via CGEvent.

**Tech Stack:** Swift 5, SwiftUI, AppKit (NSPanel), GRDB (SQLite), Carbon (hotkey), CGEvent (paste simulation). Targets macOS 13.0+.

**Spec:** `docs/superpowers/specs/2026-03-21-pasteflow-mvp-design.md`

**Important Xcode project note:** This project uses `PBXFileSystemSynchronizedRootGroup` — Xcode automatically discovers new files added to the `PasteFlow/` and `PasteFlowTests/` directories. You do NOT need to edit `project.pbxproj` when adding new Swift files. Just create the file in the right directory.

---

## Task 0: Project Setup — Disable Sandbox, Add GRDB, Restructure Directories

**Files:**
- Modify: `PasteFlow/PasteFlow.entitlements`
- Modify: `PasteFlow/Info.plist` (create if needed — set LSUIElement)
- Create: `PasteFlow/App/` directory
- Create: `PasteFlow/Models/` directory
- Create: `PasteFlow/State/` directory
- Create: `PasteFlow/Services/` directory
- Create: `PasteFlow/Views/` directory
- Create: `PasteFlow/Utilities/` directory
- Modify: `Package.swift` or Xcode SPM config for GRDB dependency

- [ ] **Step 1: Disable App Sandbox in entitlements**

Replace `PasteFlow/PasteFlow.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
</dict>
</plist>
```

- [ ] **Step 2: Set LSUIElement to hide from Dock**

Create or update `PasteFlow/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
```

Note: In modern Xcode, you may need to add this via the project's Info tab instead. Check if the target already has an Info.plist configured. If using the Info tab, add "Application is agent (UIElement)" = YES.

- [ ] **Step 3: Create directory structure**

```bash
mkdir -p PasteFlow/App PasteFlow/Models PasteFlow/State PasteFlow/Services PasteFlow/Views PasteFlow/Utilities
```

- [ ] **Step 4: Move existing files to App/ directory**

```bash
mv PasteFlow/PasteFlowApp.swift PasteFlow/App/PasteFlowApp.swift
mv PasteFlow/ContentView.swift PasteFlow/App/ContentView.swift
```

Note: ContentView.swift will be replaced in a later task but keep it for now so the project compiles.

- [ ] **Step 5: Add GRDB dependency via Swift Package Manager**

In Xcode: File > Add Package Dependencies > enter URL: `https://github.com/groue/GRDB.swift`
Select version: Up to Next Major from `7.0.0`.
Add GRDB to the PasteFlow target.

Alternatively, if using a `Package.swift` (unlikely for Xcode project), add:
```swift
.package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
```

- [ ] **Step 6: Verify the project compiles**

```bash
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "chore: disable sandbox, add GRDB dependency, restructure directories"
```

---

## Task 1: Data Models — ClipboardItem, ContentType, ImageFormat, ClipboardItemRecord

**Files:**
- Create: `PasteFlow/Models/ClipboardItem.swift`
- Create: `PasteFlow/Models/ContentType.swift`
- Create: `PasteFlow/Models/ImageFormat.swift`
- Create: `PasteFlow/Models/ClipboardItemRecord.swift`
- Test: `PasteFlowTests/Models/ClipboardItemRecordTests.swift`

- [ ] **Step 0: Create test subdirectories**

```bash
mkdir -p PasteFlowTests/Models PasteFlowTests/Services PasteFlowTests/Utilities
```

- [ ] **Step 1: Create ContentType enum**

Create `PasteFlow/Models/ContentType.swift`:

```swift
import Foundation

enum ContentType: String, Codable, CaseIterable {
    case text
    case code
    case link
    case image
}
```

- [ ] **Step 2: Create ImageFormat enum**

Create `PasteFlow/Models/ImageFormat.swift`:

```swift
import Foundation

enum ImageFormat: String, Codable {
    case png
    case tiff
    case jpeg
    case gif
    case bmp
    case pdf
}
```

- [ ] **Step 3: Create ClipboardContent and ClipboardItem**

Create `PasteFlow/Models/ClipboardItem.swift`:

```swift
import Foundation
import CryptoKit

enum ClipboardContent {
    case text(String)
    case image(Data, ImageFormat)
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
        }
    }
}
```

- [ ] **Step 4: Create ClipboardItemRecord for GRDB**

Create `PasteFlow/Models/ClipboardItemRecord.swift`:

```swift
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
    }
}
```

- [ ] **Step 5: Write tests for record conversion**

Create `PasteFlowTests/Models/ClipboardItemRecordTests.swift`:

```swift
import XCTest
@testable import PasteFlow

final class ClipboardItemRecordTests: XCTestCase {

    func testTextItemCreation() {
        let item = ClipboardItem(
            content: .text("Hello, world!"),
            sourceApp: "Safari",
            contentType: .text
        )
        XCTAssertEqual(item.characterCount, 13)
        XCTAssertNil(item.imageSize)
        XCTAssertEqual(item.contentType, .text)
        XCTAssertFalse(item.contentHash.isEmpty)
    }

    func testImageItemCreation() {
        let data = Data(repeating: 0xFF, count: 1024)
        let item = ClipboardItem(
            content: .image(data, .png),
            sourceApp: "Preview",
            contentType: .image
        )
        XCTAssertNil(item.characterCount)
        XCTAssertEqual(item.imageSize, 1024)
        XCTAssertEqual(item.contentType, .image)
        XCTAssertFalse(item.contentHash.isEmpty)
    }

    func testDuplicateTextProducesSameHash() {
        let item1 = ClipboardItem(content: .text("duplicate"), sourceApp: nil, contentType: .text)
        let item2 = ClipboardItem(content: .text("duplicate"), sourceApp: nil, contentType: .text)
        XCTAssertEqual(item1.contentHash, item2.contentHash)
    }

    func testDifferentTextProducesDifferentHash() {
        let item1 = ClipboardItem(content: .text("hello"), sourceApp: nil, contentType: .text)
        let item2 = ClipboardItem(content: .text("world"), sourceApp: nil, contentType: .text)
        XCTAssertNotEqual(item1.contentHash, item2.contentHash)
    }
}
```

- [ ] **Step 6: Run tests**

```bash
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow test -destination 'platform=macOS' 2>&1 | grep -E '(Test Case|TEST|FAIL|PASS|Build)'
```

Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add PasteFlow/Models/ PasteFlowTests/Models/
git commit -m "feat: add clipboard data models and GRDB record type"
```

---

## Task 2: Storage Layer — StorageService with GRDB

**Files:**
- Create: `PasteFlow/Services/StorageService.swift`
- Test: `PasteFlowTests/Services/StorageServiceTests.swift`

- [ ] **Step 1: Write failing tests for StorageService**

Create `PasteFlowTests/Services/StorageServiceTests.swift`:

```swift
import XCTest
@testable import PasteFlow

final class StorageServiceTests: XCTestCase {
    var storage: StorageService!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storage = try! StorageService(
            databasePath: tempDir.appendingPathComponent("test.db").path,
            imagesDirectory: tempDir.appendingPathComponent("images")
        )
    }

    override func tearDown() {
        storage = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSaveAndFetchTextItem() throws {
        let item = ClipboardItem(
            content: .text("Hello clipboard"),
            sourceApp: "Safari",
            contentType: .text
        )
        try storage.save(item)
        let fetched = try storage.fetchItems(filter: nil, search: nil, limit: 50, offset: 0)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, item.id)
        if case .text(let text) = fetched[0].content {
            XCTAssertEqual(text, "Hello clipboard")
        } else {
            XCTFail("Expected text content")
        }
    }

    func testSaveAndFetchImageItem() throws {
        let imageData = Data(repeating: 0xAB, count: 512)
        let item = ClipboardItem(
            content: .image(imageData, .png),
            sourceApp: "Preview",
            contentType: .image
        )
        try storage.save(item)
        let fetched = try storage.fetchItems(filter: nil, search: nil, limit: 50, offset: 0)
        XCTAssertEqual(fetched.count, 1)
        if case .image(let data, let format) = fetched[0].content {
            XCTAssertEqual(data, imageData)
            XCTAssertEqual(format, .png)
        } else {
            XCTFail("Expected image content")
        }
    }

    func testFilterByContentType() throws {
        let textItem = ClipboardItem(content: .text("text"), sourceApp: nil, contentType: .text)
        let codeItem = ClipboardItem(content: .text("let x = 1"), sourceApp: nil, contentType: .code)
        try storage.save(textItem)
        try storage.save(codeItem)

        let textOnly = try storage.fetchItems(filter: .text, search: nil, limit: 50, offset: 0)
        XCTAssertEqual(textOnly.count, 1)
        XCTAssertEqual(textOnly[0].contentType, .text)

        let codeOnly = try storage.fetchItems(filter: .code, search: nil, limit: 50, offset: 0)
        XCTAssertEqual(codeOnly.count, 1)
        XCTAssertEqual(codeOnly[0].contentType, .code)
    }

    func testSearchTextContent() throws {
        let item1 = ClipboardItem(content: .text("Hello world"), sourceApp: nil, contentType: .text)
        let item2 = ClipboardItem(content: .text("Goodbye moon"), sourceApp: nil, contentType: .text)
        try storage.save(item1)
        try storage.save(item2)

        let results = try storage.fetchItems(filter: nil, search: "Hello", limit: 50, offset: 0)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, item1.id)
    }

    func testDeduplication() throws {
        let item1 = ClipboardItem(content: .text("duplicate"), sourceApp: nil, contentType: .text)
        try storage.save(item1)

        // Save same content again — should replace the old item
        let item2 = ClipboardItem(content: .text("duplicate"), sourceApp: nil, contentType: .text)
        try storage.save(item2)

        let fetched = try storage.fetchItems(filter: nil, search: nil, limit: 50, offset: 0)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, item2.id) // new item replaced old
    }

    func testDeleteItem() throws {
        let item = ClipboardItem(content: .text("to delete"), sourceApp: nil, contentType: .text)
        try storage.save(item)
        try storage.delete(item.id)
        let fetched = try storage.fetchItems(filter: nil, search: nil, limit: 50, offset: 0)
        XCTAssertEqual(fetched.count, 0)
    }

    func testDeleteExpired() throws {
        let oldItem = ClipboardItem(
            id: UUID(),
            content: .text("old"),
            sourceApp: nil,
            createdAt: Date().addingTimeInterval(-31 * 24 * 3600), // 31 days ago
            contentType: .text
        )
        let newItem = ClipboardItem(content: .text("new"), sourceApp: nil, contentType: .text)
        try storage.save(oldItem)
        try storage.save(newItem)

        try storage.deleteExpired(olderThan: 30)

        let fetched = try storage.fetchItems(filter: nil, search: nil, limit: 50, offset: 0)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, newItem.id)
    }

    func testItemCount() throws {
        try storage.save(ClipboardItem(content: .text("a"), sourceApp: nil, contentType: .text))
        try storage.save(ClipboardItem(content: .text("b"), sourceApp: nil, contentType: .code))
        try storage.save(ClipboardItem(content: .text("c"), sourceApp: nil, contentType: .text))

        XCTAssertEqual(try storage.itemCount(filter: nil), 3)
        XCTAssertEqual(try storage.itemCount(filter: .text), 2)
        XCTAssertEqual(try storage.itemCount(filter: .code), 1)
    }

    func testPaginationOrdering() throws {
        // Items should come back newest first
        let item1 = ClipboardItem(
            id: UUID(), content: .text("first"), sourceApp: nil,
            createdAt: Date().addingTimeInterval(-100), contentType: .text
        )
        let item2 = ClipboardItem(
            id: UUID(), content: .text("second"), sourceApp: nil,
            createdAt: Date().addingTimeInterval(-50), contentType: .text
        )
        let item3 = ClipboardItem(content: .text("third"), sourceApp: nil, contentType: .text)
        try storage.save(item1)
        try storage.save(item2)
        try storage.save(item3)

        let page1 = try storage.fetchItems(filter: nil, search: nil, limit: 2, offset: 0)
        XCTAssertEqual(page1.count, 2)
        XCTAssertEqual(page1[0].id, item3.id) // newest first
        XCTAssertEqual(page1[1].id, item2.id)

        let page2 = try storage.fetchItems(filter: nil, search: nil, limit: 2, offset: 2)
        XCTAssertEqual(page2.count, 1)
        XCTAssertEqual(page2[0].id, item1.id)
    }

    func testDeleteImageRemovesFile() throws {
        let imageData = Data(repeating: 0xCD, count: 256)
        let item = ClipboardItem(content: .image(imageData, .png), sourceApp: nil, contentType: .image)
        try storage.save(item)

        // Verify image file exists
        let imagePath = tempDir.appendingPathComponent("images")
            .appendingPathComponent("\(item.id.uuidString).png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagePath.path))

        try storage.delete(item.id)

        // Verify image file is deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: imagePath.path))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow test -destination 'platform=macOS' 2>&1 | grep -E '(error:|FAIL|BUILD)'
```

Expected: Build fails — `StorageService` does not exist.

- [ ] **Step 3: Implement StorageService**

Create `PasteFlow/Services/StorageService.swift`:

```swift
import Foundation
import GRDB
import os.log

final class StorageService {
    private let dbQueue: DatabaseQueue
    private let imagesDirectory: URL
    private let logger = Logger(subsystem: "com.github.h3n4l.PasteFlow", category: "Storage")

    init(databasePath: String, imagesDirectory: URL) throws {
        // Create images directory
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        // Open database
        dbQueue = try DatabaseQueue(path: databasePath)

        // Create table
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

            // Index for fast lookups
            try db.create(index: "idx_content_hash", on: ClipboardItemRecord.databaseTableName,
                          columns: ["contentHash"], ifNotExists: true)
            try db.create(index: "idx_created_at", on: ClipboardItemRecord.databaseTableName,
                          columns: ["createdAt"], ifNotExists: true)
            try db.create(index: "idx_content_type", on: ClipboardItemRecord.databaseTableName,
                          columns: ["contentType"], ifNotExists: true)
        }
    }

    /// Default initializer using standard app support directory.
    convenience init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let pasteFlowDir = appSupport.appendingPathComponent("PasteFlow")
        try FileManager.default.createDirectory(at: pasteFlowDir, withIntermediateDirectories: true)
        let dbPath = pasteFlowDir.appendingPathComponent("clipboard.db").path
        let imagesDir = pasteFlowDir.appendingPathComponent("images")
        try self.init(databasePath: dbPath, imagesDirectory: imagesDir)
    }

    func save(_ item: ClipboardItem) throws {
        // Handle image file storage
        var imagePath: String? = nil
        if case .image(let data, let format) = item.content {
            let filename = "\(item.id.uuidString).\(format.rawValue)"
            let fileURL = imagesDirectory.appendingPathComponent(filename)
            try data.write(to: fileURL)
            imagePath = filename
        }

        let record = ClipboardItemRecord(
            id: item.id.uuidString,
            contentType: item.contentType.rawValue,
            textContent: {
                if case .text(let text) = item.content { return text }
                return nil
            }(),
            imagePath: imagePath,
            imageFormat: {
                if case .image(_, let format) = item.content { return format.rawValue }
                return nil
            }(),
            sourceApp: item.sourceApp,
            createdAt: item.createdAt.timeIntervalSince1970,
            characterCount: item.characterCount,
            imageSize: item.imageSize,
            contentHash: item.contentHash
        )

        try dbQueue.write { db in
            // Deduplication: find duplicates FIRST (to get image paths), then delete
            let duplicates = try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.contentHash == item.contentHash)
                .fetchAll(db)

            // Delete duplicate image files from disk
            for dup in duplicates {
                if let dupImagePath = dup.imagePath {
                    let fileURL = imagesDirectory.appendingPathComponent(dupImagePath)
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }

            // Delete duplicate records from database
            try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.contentHash == item.contentHash)
                .deleteAll(db)

            // Insert the new record
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
                // Escape LIKE wildcards in user input
                let escaped = search
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                query = query.filter(ClipboardItemRecord.Columns.textContent.like("%\(escaped)%", escape: "\\"))
            }

            query = query.order(ClipboardItemRecord.Columns.createdAt.desc)
                .limit(limit, offset: offset)

            let records = try query.fetchAll(db)
            return try records.map { try self.recordToItem($0) }
        }
    }

    func delete(_ id: UUID) throws {
        try dbQueue.write { db in
            // Find the record to get image path
            if let record = try ClipboardItemRecord.fetchOne(db, key: id.uuidString) {
                if let imagePath = record.imagePath {
                    let fileURL = imagesDirectory.appendingPathComponent(imagePath)
                    try? FileManager.default.removeItem(at: fileURL)
                }
                try record.delete(db)
            }
        }
    }

    func deleteExpired(olderThan days: Int) throws {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        try dbQueue.write { db in
            // Find expired records to delete their image files
            let expired = try ClipboardItemRecord
                .filter(ClipboardItemRecord.Columns.createdAt < cutoff.timeIntervalSince1970)
                .fetchAll(db)
            for record in expired {
                if let imagePath = record.imagePath {
                    let fileURL = imagesDirectory.appendingPathComponent(imagePath)
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

    /// Loads the full image data for an item. Call this only when the detail
    /// panel needs to display the image, not when listing items.
    func loadImageData(for item: ClipboardItem) -> Data? {
        guard case .image(_, let format) = item.content else { return nil }
        // If data is already a placeholder (empty), load from disk
        let filename = "\(item.id.uuidString).\(format.rawValue)"
        let fileURL = imagesDirectory.appendingPathComponent(filename)
        return try? Data(contentsOf: fileURL)
    }

    // MARK: - Private

    private func recordToItem(_ record: ClipboardItemRecord) throws -> ClipboardItem {
        let content: ClipboardContent
        let contentType = ContentType(rawValue: record.contentType) ?? .text

        if contentType == .image,
           let formatStr = record.imageFormat,
           let format = ImageFormat(rawValue: formatStr) {
            // Lazy loading: store empty placeholder data for list display.
            // Actual image data is loaded on demand via loadImageData(for:).
            content = .image(Data(), format)
        } else {
            content = .text(record.textContent ?? "")
        }

        return ClipboardItem(
            id: UUID(uuidString: record.id) ?? UUID(),
            content: content,
            sourceApp: record.sourceApp,
            createdAt: Date(timeIntervalSince1970: record.createdAt),
            contentType: contentType
        )
    }
}
```

Note: The `ClipboardItem.init` is called here which recomputes the hash. We need to add an internal init that accepts a pre-computed hash. Update `ClipboardItem.swift` to add:

```swift
// Add this internal init to ClipboardItem for database reconstruction
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
```

And update `recordToItem` to use this init:

```swift
return ClipboardItem(
    id: UUID(uuidString: record.id) ?? UUID(),
    content: content,
    sourceApp: record.sourceApp,
    createdAt: Date(timeIntervalSince1970: record.createdAt),
    contentType: contentType,
    characterCount: record.characterCount,
    imageSize: record.imageSize,
    contentHash: record.contentHash
)
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow test -destination 'platform=macOS' 2>&1 | grep -E '(Test Case|FAIL|PASS|error:)'
```

Expected: All StorageServiceTests pass.

- [ ] **Step 5: Commit**

```bash
git add PasteFlow/Services/StorageService.swift PasteFlow/Models/ClipboardItem.swift PasteFlowTests/Services/
git commit -m "feat: add StorageService with GRDB persistence and image file storage"
```

---

## Task 3: ContentClassifier — Auto-detect text, code, and link types

**Files:**
- Create: `PasteFlow/Utilities/ContentClassifier.swift`
- Test: `PasteFlowTests/Utilities/ContentClassifierTests.swift`

- [ ] **Step 1: Write failing tests**

Create `PasteFlowTests/Utilities/ContentClassifierTests.swift`:

```swift
import XCTest
@testable import PasteFlow

final class ContentClassifierTests: XCTestCase {

    func testPlainTextClassification() {
        XCTAssertEqual(ContentClassifier.classify("Hello, world!"), .text)
        XCTAssertEqual(ContentClassifier.classify("Meeting notes from today"), .text)
        XCTAssertEqual(ContentClassifier.classify("Buy milk and eggs"), .text)
    }

    func testURLClassification() {
        XCTAssertEqual(ContentClassifier.classify("https://github.com/h3n4l/PasteFlow"), .link)
        XCTAssertEqual(ContentClassifier.classify("http://example.com"), .link)
        XCTAssertEqual(ContentClassifier.classify("https://www.apple.com/macos"), .link)
    }

    func testCodeClassification() {
        XCTAssertEqual(ContentClassifier.classify("let x = 42\nvar y = x + 1"), .code)
        XCTAssertEqual(ContentClassifier.classify("func hello() {\n    print(\"hi\")\n}"), .code)
        XCTAssertEqual(ContentClassifier.classify("import Foundation\nclass Foo {}"), .code)
        XCTAssertEqual(ContentClassifier.classify("def main():\n    return 0"), .code)
        XCTAssertEqual(ContentClassifier.classify("const x = { key: value };"), .code)
    }

    func testCodeTakesPriorityOverLink() {
        // URL inside code block — should be classified as code
        let codeWithURL = "let url = \"https://api.example.com/v1\"\nlet request = URLRequest(url: url)"
        XCTAssertEqual(ContentClassifier.classify(codeWithURL), .code)
    }

    func testSingleKeywordIsNotCode() {
        // Just one signal is not enough — need minimum 2
        XCTAssertEqual(ContentClassifier.classify("let me know if this works"), .text)
        XCTAssertEqual(ContentClassifier.classify("I need to import this file"), .text)
    }

    func testEmptyStringIsText() {
        XCTAssertEqual(ContentClassifier.classify(""), .text)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow test -destination 'platform=macOS' 2>&1 | grep -E '(error:|FAIL|BUILD)'
```

Expected: Build fails — `ContentClassifier` does not exist.

- [ ] **Step 3: Implement ContentClassifier**

Create `PasteFlow/Utilities/ContentClassifier.swift`:

```swift
import Foundation

enum ContentClassifier {

    /// Classifies text content.
    /// Priority: if the entire text is a single URL -> .link.
    /// If multi-line or has 2+ code signals -> .code (even if URLs present).
    /// Otherwise -> .text.
    static func classify(_ text: String) -> ContentType {
        guard !text.isEmpty else { return .text }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Single-line URL check first — a bare URL is always a link
        if !trimmed.contains("\n") && looksLikeURL(trimmed) {
            return .link
        }

        // Code detection — minimum 2 signals required
        let codeScore = codeSignalCount(text)
        if codeScore >= 2 {
            return .code
        }

        return .text
    }

    // MARK: - Private

    private static let urlPattern: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"^https?://[^\s]+$"#,
            options: [.caseInsensitive]
        )
    }()

    private static func looksLikeURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return urlPattern.firstMatch(in: trimmed, range: range) != nil
    }

    private static let codeKeywords: Set<String> = [
        "func", "class", "struct", "enum", "protocol", "extension",
        "import", "return", "guard", "switch", "case",
        "let", "var", "const", "def", "fn", "pub",
        "if", "else", "for", "while",
        "async", "await", "throws", "try", "catch",
        "public", "private", "static", "override",
        "self", "nil", "true", "false",
    ]

    private static func codeSignalCount(_ text: String) -> Int {
        var score = 0

        // Signal: contains braces {} or brackets []
        if text.contains("{") && text.contains("}") { score += 1 }

        // Signal: contains semicolons at end of lines
        if text.contains(";") { score += 1 }

        // Signal: contains indentation (lines starting with spaces/tabs)
        let lines = text.components(separatedBy: .newlines)
        let indentedLines = lines.filter { $0.hasPrefix("    ") || $0.hasPrefix("\t") }
        if indentedLines.count >= 1 { score += 1 }

        // Signal: contains code keywords (word-boundary match)
        let words = Set(
            text.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        let keywordMatches = words.intersection(codeKeywords).count
        if keywordMatches >= 2 { score += 1 }
        if keywordMatches >= 4 { score += 1 }

        // Signal: parentheses suggesting function calls/definitions
        if text.contains("(") && text.contains(")") { score += 1 }

        // Signal: assignment operators
        let assignmentPattern = try? NSRegularExpression(pattern: #"\s[=!<>]=?\s"#)
        let range = NSRange(text.startIndex..., in: text)
        if let matches = assignmentPattern?.numberOfMatches(in: text, range: range), matches > 0 {
            score += 1
        }

        return score
    }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow test -destination 'platform=macOS' 2>&1 | grep -E '(Test Case|FAIL|PASS)'
```

Expected: All ContentClassifierTests pass.

- [ ] **Step 5: Commit**

```bash
git add PasteFlow/Utilities/ContentClassifier.swift PasteFlowTests/Utilities/
git commit -m "feat: add ContentClassifier for auto-detecting text, code, and link types"
```

---

## Task 4: ClipboardMonitor — Poll NSPasteboard for new clipboard content

**Files:**
- Create: `PasteFlow/Services/ClipboardMonitor.swift`

- [ ] **Step 1: Implement ClipboardMonitor**

Create `PasteFlow/Services/ClipboardMonitor.swift`:

```swift
import AppKit
import Foundation
import os.log

final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int
    private let storage: StorageService
    private let onNewItem: (ClipboardItem) -> Void
    private let logger = Logger(subsystem: "com.github.h3n4l.PasteFlow", category: "ClipboardMonitor")

    /// Set to true temporarily when PasteSimulator writes to the pasteboard,
    /// so ClipboardMonitor ignores the self-triggered change.
    var suppressNextChange = false

    init(storage: StorageService, onNewItem: @escaping (ClipboardItem) -> Void) {
        self.storage = storage
        self.onNewItem = onNewItem
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        // Skip self-triggered changes from PasteSimulator
        if suppressNextChange {
            suppressNextChange = false
            return
        }

        // Get the source app before reading pasteboard
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName

        // Try to read image first (higher fidelity), then text
        if let item = readImage(from: pasteboard, sourceApp: sourceApp) {
            saveAndNotify(item)
        } else if let item = readText(from: pasteboard, sourceApp: sourceApp) {
            saveAndNotify(item)
        }
    }

    private func readText(from pasteboard: NSPasteboard, sourceApp: String?) -> ClipboardItem? {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return nil }
        let contentType = ContentClassifier.classify(text)
        return ClipboardItem(
            content: .text(text),
            sourceApp: sourceApp,
            contentType: contentType
        )
    }

    private func readImage(from pasteboard: NSPasteboard, sourceApp: String?) -> ClipboardItem? {
        // Check for image types in order of preference
        let typeFormatMap: [(NSPasteboard.PasteboardType, ImageFormat)] = [
            (.png, .png),
            (.tiff, .tiff),
        ]

        for (pasteboardType, format) in typeFormatMap {
            if let data = pasteboard.data(forType: pasteboardType) {
                return ClipboardItem(
                    content: .image(data, format),
                    sourceApp: sourceApp,
                    contentType: .image
                )
            }
        }

        // Fallback: try to get NSImage and convert to TIFF
        if let _ = pasteboard.data(forType: .pdf) {
            if let data = pasteboard.data(forType: .pdf) {
                return ClipboardItem(
                    content: .image(data, .pdf),
                    sourceApp: sourceApp,
                    contentType: .image
                )
            }
        }

        return nil
    }

    private func saveAndNotify(_ item: ClipboardItem) {
        do {
            try storage.save(item)
            DispatchQueue.main.async {
                self.onNewItem(item)
            }
        } catch {
            logger.error("Failed to save clipboard item: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 2: Verify project compiles**

```bash
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PasteFlow/Services/ClipboardMonitor.swift
git commit -m "feat: add ClipboardMonitor for polling NSPasteboard"
```

---

## Task 5: HotkeyService — Global Cmd+Shift+V hotkey via Carbon API

**Files:**
- Create: `PasteFlow/Services/HotkeyService.swift`

- [ ] **Step 1: Implement HotkeyService**

Create `PasteFlow/Services/HotkeyService.swift`:

```swift
import Carbon
import Foundation
import os.log

final class HotkeyService {
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let logger = Logger(subsystem: "com.github.h3n4l.PasteFlow", category: "HotkeyService")

    var onHotkeyPressed: (() -> Void)?

    // Singleton to bridge C callback
    static var shared: HotkeyService?

    func register() {
        HotkeyService.shared = self

        // Cmd+Shift+V
        // V key code = 9, Cmd = cmdKey, Shift = shiftKey
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x5046_4C57) // "PFLW"
        hotKeyID.id = 1

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            guard let event = event else { return OSStatus(eventNotHandledErr) }

            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if hotKeyID.id == 1 {
                DispatchQueue.main.async {
                    HotkeyService.shared?.onHotkeyPressed?()
                }
            }

            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status != noErr {
            logger.error("Failed to register hotkey: \(status)")
        } else {
            logger.info("Global hotkey Cmd+Shift+V registered")
        }
    }

    func unregister() {
        if let hotkeyRef = hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        HotkeyService.shared = nil
    }

    deinit {
        unregister()
    }
}
```

- [ ] **Step 2: Verify project compiles**

```bash
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PasteFlow/Services/HotkeyService.swift
git commit -m "feat: add HotkeyService for global Cmd+Shift+V registration via Carbon"
```

---

## Task 6: PasteSimulator — Copy to pasteboard and simulate Cmd+V

**Files:**
- Create: `PasteFlow/Services/PasteSimulator.swift`

- [ ] **Step 1: Implement PasteSimulator**

Create `PasteFlow/Services/PasteSimulator.swift`:

```swift
import AppKit
import Foundation
import os.log

enum PasteSimulator {
    private static let logger = Logger(subsystem: "com.github.h3n4l.PasteFlow", category: "PasteSimulator")

    /// Returns true if accessibility is granted.
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant accessibility permission.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Copies the item to the pasteboard and simulates Cmd+V.
    /// If accessibility is not granted, only copies to pasteboard (manual paste mode).
    /// Pass the clipboardMonitor so we can suppress the self-triggered change.
    static func paste(_ item: ClipboardItem, clipboardMonitor: ClipboardMonitor? = nil) {
        clipboardMonitor?.suppressNextChange = true
        copyToPasteboard(item)

        guard isAccessibilityGranted else {
            logger.info("Accessibility not granted — copied to clipboard only (manual paste mode)")
            return
        }

        // Small delay to allow panel to dismiss and frontmost app to activate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            simulateCmdV()
        }
    }

    // MARK: - Private

    private static func copyToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let data, let format):
            let type = pasteboardType(for: format)
            pasteboard.setData(data, forType: type)
        }
    }

    private static func pasteboardType(for format: ImageFormat) -> NSPasteboard.PasteboardType {
        switch format {
        case .png: return .png
        case .tiff: return .tiff
        case .jpeg: return NSPasteboard.PasteboardType("public.jpeg")
        case .gif: return NSPasteboard.PasteboardType("com.compuserve.gif")
        case .bmp: return NSPasteboard.PasteboardType("com.microsoft.bmp")
        case .pdf: return .pdf
        }
    }

    private static func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down: Cmd + V (keycode 9)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            logger.error("Failed to create CGEvent for paste simulation")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 2: Verify project compiles**

```bash
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PasteFlow/Services/PasteSimulator.swift
git commit -m "feat: add PasteSimulator for clipboard copy and Cmd+V simulation"
```

---

## Task 7: AppState — Central ObservableObject

**Files:**
- Create: `PasteFlow/State/AppState.swift`

- [ ] **Step 1: Implement AppState**

Create `PasteFlow/State/AppState.swift`:

```swift
import Combine
import Foundation
import os.log

final class AppState: ObservableObject {
    @Published var clipboardItems: [ClipboardItem] = []
    @Published var selectedItem: ClipboardItem?
    @Published var searchText: String = ""
    @Published var activeFilter: ContentType?
    @Published var totalItemCount: Int = 0
    @Published var statusMessage: String?

    let storage: StorageService
    let clipboardMonitor: ClipboardMonitor
    let hotkeyService: HotkeyService

    private let pageSize = 50
    private var hasMoreItems = true
    private let logger = Logger(subsystem: "com.github.h3n4l.PasteFlow", category: "AppState")
    private var searchDebounce: AnyCancellable?
    private var cleanupTimer: Timer?

    init(storage: StorageService) {
        self.storage = storage
        self.hotkeyService = HotkeyService()

        // Temporary placeholder — will be set properly after init
        var monitor: ClipboardMonitor!
        monitor = ClipboardMonitor(storage: storage) { [weak self] _ in
            self?.reloadItems()
        }
        self.clipboardMonitor = monitor

        // Debounce search text changes
        searchDebounce = $searchText
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.reloadItems()
            }

        // Reload when filter changes
        // (handled manually since we call reloadItems)

        reloadItems()
        cleanupExpired()

        // Schedule cleanup every 24 hours
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            self?.cleanupExpired()
        }
    }

    var filteredItems: [ClipboardItem] {
        clipboardItems
    }

    func reloadItems() {
        do {
            clipboardItems = try storage.fetchItems(
                filter: activeFilter,
                search: searchText.isEmpty ? nil : searchText,
                limit: pageSize,
                offset: 0
            )
            totalItemCount = try storage.itemCount(filter: activeFilter)
            hasMoreItems = clipboardItems.count < totalItemCount

            // Auto-select first item if none selected
            if selectedItem == nil || !clipboardItems.contains(where: { $0.id == selectedItem?.id }) {
                selectedItem = clipboardItems.first
            }
        } catch {
            logger.error("Failed to reload items: \(error.localizedDescription)")
            statusMessage = "Failed to load clipboard history"
        }
    }

    func loadMoreItems() {
        guard hasMoreItems else { return }
        do {
            let moreItems = try storage.fetchItems(
                filter: activeFilter,
                search: searchText.isEmpty ? nil : searchText,
                limit: pageSize,
                offset: clipboardItems.count
            )
            clipboardItems.append(contentsOf: moreItems)
            hasMoreItems = clipboardItems.count < totalItemCount
        } catch {
            logger.error("Failed to load more items: \(error.localizedDescription)")
        }
    }

    func setFilter(_ filter: ContentType?) {
        activeFilter = filter
        reloadItems()
    }

    func deleteItem(_ item: ClipboardItem) {
        do {
            try storage.delete(item.id)
            reloadItems()
        } catch {
            logger.error("Failed to delete item: \(error.localizedDescription)")
            statusMessage = "Failed to delete item"
        }
    }

    func pasteItem(_ item: ClipboardItem) {
        PasteSimulator.paste(item, clipboardMonitor: clipboardMonitor)
    }

    func selectNext() {
        guard !clipboardItems.isEmpty else { return }
        if let current = selectedItem,
           let index = clipboardItems.firstIndex(where: { $0.id == current.id }),
           index + 1 < clipboardItems.count {
            selectedItem = clipboardItems[index + 1]
        }
    }

    func selectPrevious() {
        guard !clipboardItems.isEmpty else { return }
        if let current = selectedItem,
           let index = clipboardItems.firstIndex(where: { $0.id == current.id }),
           index > 0 {
            selectedItem = clipboardItems[index - 1]
        }
    }

    // MARK: - Private

    private func cleanupExpired() {
        let retentionDays = UserDefaults.standard.integer(forKey: "retentionDays")
        let days = retentionDays > 0 ? retentionDays : 30
        do {
            try storage.deleteExpired(olderThan: days)
        } catch {
            logger.error("Failed to clean expired items: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 2: Verify project compiles**

```bash
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PasteFlow/State/AppState.swift
git commit -m "feat: add AppState as central ObservableObject for UI state management"
```

---

## Task 8: FloatingPanel — NSPanel subclass for the popup window

**Files:**
- Create: `PasteFlow/Views/FloatingPanel.swift`

- [ ] **Step 1: Implement FloatingPanel**

Create `PasteFlow/Views/FloatingPanel.swift`:

```swift
import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 456),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Panel configuration
        self.isFloatingPanel = true
        self.level = .floating
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true

        // Set content
        self.contentView = contentView

        // Round corners
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.cornerRadius = 12
        self.contentView?.layer?.masksToBounds = true
    }

    /// Centers the panel on the main screen.
    func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = self.frame
        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.midY - panelFrame.height / 2
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Shows the panel centered on screen.
    func showPanel() {
        centerOnScreen()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hides the panel.
    func hidePanel() {
        orderOut(nil)
    }

    /// Toggles the panel visibility.
    func toggle() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    // Dismiss on Esc
    override func cancelOperation(_ sender: Any?) {
        hidePanel()
    }

    // Dismiss on click outside
    override func resignKey() {
        super.resignKey()
        hidePanel()
    }
}
```

- [ ] **Step 2: Verify project compiles**

```bash
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PasteFlow/Views/FloatingPanel.swift
git commit -m "feat: add FloatingPanel NSPanel subclass for centered popup window"
```

---

## Task 9: SwiftUI Views — SearchBar, FilterRow, ClipRow, DetailPanel, Footer, PopoverView

**Files:**
- Create: `PasteFlow/Utilities/Extensions.swift`
- Create: `PasteFlow/Views/SearchBarView.swift`
- Create: `PasteFlow/Views/FilterRowView.swift`
- Create: `PasteFlow/Views/ClipRowView.swift`
- Create: `PasteFlow/Views/ClipListView.swift`
- Create: `PasteFlow/Views/DetailPanelView.swift`
- Create: `PasteFlow/Views/FooterView.swift`
- Create: `PasteFlow/Views/PopoverView.swift`

This is a large task. Build each view one at a time, verify it compiles, then move on.

- [ ] **Step 1: Create SearchBarView**

Create `PasteFlow/Views/SearchBarView.swift`:

```swift
import SwiftUI

struct SearchBarView: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color(hex: 0x999999))
                .font(.system(size: 14))

            TextField("Search clipboard...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            Spacer()

            Text("Cmd+Shift+V")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: 0x999999))
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(hex: 0xE5E5E5)),
            alignment: .bottom
        )
    }
}
```

- [ ] **Step 2: Create FilterRowView**

Create `PasteFlow/Views/FilterRowView.swift`:

```swift
import SwiftUI

struct FilterRowView: View {
    @Binding var activeFilter: ContentType?

    private let filters: [(label: String, type: ContentType?)] = [
        ("All", nil),
        ("Text", .text),
        ("Link", .link),
        ("Code", .code),
        ("Image", .image),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(filters, id: \.label) { filter in
                FilterPill(
                    label: filter.label,
                    isActive: activeFilter == filter.type,
                    action: { activeFilter = filter.type }
                )
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 32)
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(hex: 0xE5E5E5)),
            alignment: .bottom
        )
    }
}

private struct FilterPill: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: 0x3C3489))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(isActive ? Color(hex: 0xEEEDFE) : Color.clear)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color(hex: 0xCECBF6), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: Create ClipRowView**

Create `PasteFlow/Views/ClipRowView.swift`:

```swift
import SwiftUI

struct ClipRowView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let shortcutIndex: Int?

    var body: some View {
        HStack(spacing: 8) {
            // Type icon
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? Color(hex: 0x185FA5) : Color(hex: 0x999999))
                .frame(width: 12, height: 12)

            // Content area
            VStack(alignment: .leading, spacing: 2) {
                Text(previewText)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? Color(hex: 0x185FA5) : Color(hex: 0x1A1A1A))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(metadataText)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected
                        ? Color(hex: 0x185FA5).opacity(0.6)
                        : Color(hex: 0x999999))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Shortcut label
            if let index = shortcutIndex, index < 9 {
                Text("Cmd+\(index + 1)")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected
                        ? Color(hex: 0x185FA5).opacity(0.5)
                        : Color(hex: 0x999999))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(height: 44)
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
        case .text(let text):
            return text.replacingOccurrences(of: "\n", with: " ")
        case .image(_, let format):
            return "Image (\(format.rawValue.uppercased()))"
        }
    }

    private var metadataText: String {
        let timeAgo = item.createdAt.relativeString()
        switch item.content {
        case .text(let text):
            if item.contentType == .link {
                if let host = URL(string: text)?.host {
                    return "\(timeAgo) · \(host)"
                }
            }
            return "\(timeAgo) · \(text.count) chars"
        case .image(let data, _):
            return "\(timeAgo) · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
        }
    }
}
```

- [ ] **Step 4: Create a Date extension and Color extension for helpers**

Add to `PasteFlow/Utilities/Extensions.swift` (create this file):

```swift
import SwiftUI

// MARK: - Date Relative Formatting
extension Date {
    func relativeString() -> String {
        let interval = Date().timeIntervalSince(self)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 7 * 86400 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: self)
        }
    }
}

// MARK: - Color from Hex
extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
```

- [ ] **Step 5: Create ClipListView**

Create `PasteFlow/Views/ClipListView.swift`:

```swift
import SwiftUI

struct ClipListView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(appState.filteredItems.enumerated()), id: \.element.id) { index, item in
                        ClipRowView(
                            item: item,
                            isSelected: appState.selectedItem?.id == item.id,
                            shortcutIndex: index
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.selectedItem = item
                        }
                        .onAppear {
                            // Load more when approaching the end
                            if index == appState.filteredItems.count - 5 {
                                appState.loadMoreItems()
                            }
                        }
                    }
                }
            }
            .onChange(of: appState.selectedItem?.id) { _ in
                if let selectedId = appState.selectedItem?.id {
                    withAnimation {
                        proxy.scrollTo(selectedId, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 340)
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(hex: 0xE5E5E5)),
            alignment: .trailing
        )
    }
}
```

- [ ] **Step 6: Create DetailPanelView**

Create `PasteFlow/Views/DetailPanelView.swift`:

```swift
import SwiftUI

struct DetailPanelView: View {
    let item: ClipboardItem?
    let onPaste: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void

    var body: some View {
        if let item = item {
            VStack(alignment: .leading, spacing: 10) {
                // PREVIEW label
                Text("PREVIEW")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: 0x666666))
                    .tracking(0.5)

                // Preview content
                previewBlock(for: item)

                // Metadata
                metadataSection(for: item)

                // Action buttons
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
        }
    }

    private func metadataSection(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch item.content {
            case .text(let text):
                Text("\(item.contentType.rawValue.capitalized) · \(text.count) characters")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0x999999))
            case .image(let data, let format):
                Text("\(format.rawValue.uppercased()) · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0x999999))
            }

            Text("Copied \(item.createdAt.relativeString())")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: 0x999999))

            if let sourceApp = item.sourceApp {
                Text("Source: \(sourceApp)")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0x999999))
            }
        }
    }

    private func actionButtons(for item: ClipboardItem) -> some View {
        HStack(spacing: 6) {
            Button(action: { onPaste(item) }) {
                Text("Paste")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0x3C3489))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: 0xEEEDFE))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(hex: 0xE5E5E5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(action: { onDelete(item) }) {
                Text("Delete")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0x3C3489))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(hex: 0xE5E5E5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
```

- [ ] **Step 7: Create FooterView**

Create `PasteFlow/Views/FooterView.swift`:

```swift
import SwiftUI

struct FooterView: View {
    let itemCount: Int
    let statusMessage: String?
    let isAccessibilityGranted: Bool

    var body: some View {
        HStack {
            if let message = statusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.7))
            } else if !isAccessibilityGranted {
                Text("Accessibility: off — manual paste mode")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0x999999))
            }

            Spacer()

            Text("\(itemCount) items")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: 0x999999))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(height: 27)
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(hex: 0xE5E5E5)),
            alignment: .top
        )
    }
}
```

- [ ] **Step 8: Create PopoverView (root view)**

Create `PasteFlow/Views/PopoverView.swift`:

```swift
import SwiftUI

struct PopoverView: View {
    @ObservedObject var appState: AppState
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SearchBarView(searchText: $appState.searchText)

            FilterRowView(activeFilter: Binding(
                get: { appState.activeFilter },
                set: { appState.setFilter($0) }
            ))

            HStack(spacing: 0) {
                ClipListView(appState: appState)

                DetailPanelView(
                    item: appState.selectedItem,
                    onPaste: { item in
                        appState.pasteItem(item)
                        onDismiss()
                    },
                    onDelete: { item in
                        appState.deleteItem(item)
                    }
                )
                .frame(width: 220)
            }
            .frame(maxHeight: .infinity)

            FooterView(
                itemCount: appState.totalItemCount,
                statusMessage: appState.statusMessage,
                isAccessibilityGranted: PasteSimulator.isAccessibilityGranted
            )
        }
        .frame(width: 560, height: 456)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: 0xE5E5E5), lineWidth: 1)
        )
        .onExitCommand {
            onDismiss()
        }
    }
}
```

- [ ] **Step 9: Verify all views compile**

```bash
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 10: Commit**

```bash
git add PasteFlow/Views/ PasteFlow/Utilities/Extensions.swift
git commit -m "feat: add all SwiftUI views — search, filters, clip list, detail panel, popover"
```

---

## Task 10: App Lifecycle — AppDelegate, PasteFlowApp, Keyboard Handling

**Files:**
- Create: `PasteFlow/App/AppDelegate.swift`
- Modify: `PasteFlow/App/PasteFlowApp.swift`
- Delete: `PasteFlow/App/ContentView.swift`

- [ ] **Step 1: Create AppDelegate**

Create `PasteFlow/App/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let storage = try createStorage()
            let state = AppState(storage: storage)
            self.appState = state

            // Create the floating panel with SwiftUI content
            let popoverView = PopoverView(appState: state) { [weak self] in
                self?.panel?.hidePanel()
            }
            let hostingView = NSHostingView(rootView: popoverView)
            hostingView.frame = NSRect(x: 0, y: 0, width: 560, height: 456)

            let panel = FloatingPanel(contentView: hostingView)
            self.panel = panel

            // Register global hotkey
            state.hotkeyService.onHotkeyPressed = { [weak self] in
                self?.togglePanel()
            }
            state.hotkeyService.register()

            // Start clipboard monitoring
            state.clipboardMonitor.start()

            // Check accessibility on launch
            if !PasteSimulator.isAccessibilityGranted {
                showAccessibilityDialog()
            }
        } catch {
            // Fatal: can't start without storage
            let alert = NSAlert()
            alert.messageText = "PasteFlow Failed to Start"
            alert.informativeText = "Could not initialize storage: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func togglePanel() {
        panel?.toggle()
        if panel?.isVisible == true {
            appState?.reloadItems()
            // Re-check accessibility each time panel is shown
            appState?.objectWillChange.send()
        }
    }

    /// Attempts to create StorageService. On corruption, deletes the database and retries.
    private func createStorage() throws -> StorageService {
        do {
            return try StorageService()
        } catch {
            // Database may be corrupted — try a fresh database
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dbPath = appSupport.appendingPathComponent("PasteFlow/clipboard.db")
            try? FileManager.default.removeItem(at: dbPath)
            return try StorageService()
        }
    }

    private func showAccessibilityDialog() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Needed"
        alert.informativeText = "PasteFlow needs Accessibility access to paste items into your apps. Without it, you can still copy items from history, but automatic pasting won't work."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            PasteSimulator.requestAccessibility()
        }
    }

    func openSettings() {
        // Opens the Settings scene
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
```

- [ ] **Step 2: Rewrite PasteFlowApp.swift**

Replace `PasteFlow/App/PasteFlowApp.swift`:

```swift
import SwiftUI

@main
struct PasteFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("PasteFlow", image: "MenuBarIcon") {
            Button("Open PasteFlow") {
                appDelegate.togglePanel()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Divider()

            Button("Settings...") {
                appDelegate.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Quit PasteFlow") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState!)
        }
    }
}
```

- [ ] **Step 3: Create a placeholder SettingsView**

Create `PasteFlow/Views/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Text("Settings — coming in Task 11")
            .frame(width: 400, height: 300)
    }
}
```

- [ ] **Step 4: Delete ContentView.swift**

```bash
rm PasteFlow/App/ContentView.swift
```

- [ ] **Step 5: Verify the app compiles and launches**

```bash
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

Optionally run the app to verify the menu bar icon appears and Cmd+Shift+V shows the panel. Manual testing only — the UI integration is hard to unit test.

- [ ] **Step 6: Commit**

```bash
git add PasteFlow/App/ PasteFlow/Views/SettingsView.swift
git commit -m "feat: wire up AppDelegate, MenuBarExtra, and FloatingPanel lifecycle"
```

---

## Task 11: Settings View — Retention, Launch at Login, Clear History

**Files:**
- Modify: `PasteFlow/Views/SettingsView.swift`

- [ ] **Step 1: Implement SettingsView**

Replace `PasteFlow/Views/SettingsView.swift`:

```swift
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("retentionDays") private var retentionDays: Int = 30
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @State private var showClearConfirmation = false

    private let retentionOptions = [7, 14, 30, 60, 90]

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            storageTab
                .tabItem {
                    Label("Storage", systemImage: "internaldrive")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 400, height: 250)
    }

    private var generalTab: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = !newValue // revert on failure
                    }
                }

            LabeledContent("Global hotkey") {
                Text("Cmd+Shift+V")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private var storageTab: some View {
        Form {
            Picker("Keep history for", selection: $retentionDays) {
                ForEach(retentionOptions, id: \.self) { days in
                    Text("\(days) days").tag(days)
                }
            }

            Button("Clear All History") {
                showClearConfirmation = true
            }
            .alert("Clear All History?", isPresented: $showClearConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    clearAllHistory()
                }
            } message: {
                Text("This will permanently delete all clipboard history. This cannot be undone.")
            }
        }
        .padding()
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text("PasteFlow")
                .font(.headline)

            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .foregroundColor(.secondary)

            Link("GitHub", destination: URL(string: "https://github.com/h3n4l/PasteFlow")!)
                .foregroundColor(.blue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clearAllHistory() {
        do {
            try appState.storage.deleteExpired(olderThan: 0)
            appState.reloadItems()
        } catch {
            // Silently fail — logged inside StorageService
        }
    }
}
```

- [ ] **Step 2: Verify project compiles**

```bash
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PasteFlow/Views/SettingsView.swift
git commit -m "feat: add SettingsView with retention, launch at login, and clear history"
```

---

## Task 12: Keyboard Navigation — Arrow keys, Enter to paste, Cmd+1-9 shortcuts

**Files:**
- Modify: `PasteFlow/Views/PopoverView.swift`

- [ ] **Step 1: Add keyboard event handling to PopoverView**

Update `PopoverView` to add keyboard handling. Replace the body with a version that wraps in a keyboard-capturing view:

```swift
import SwiftUI

struct PopoverView: View {
    @ObservedObject var appState: AppState
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SearchBarView(searchText: $appState.searchText)

            FilterRowView(activeFilter: Binding(
                get: { appState.activeFilter },
                set: { appState.setFilter($0) }
            ))

            HStack(spacing: 0) {
                ClipListView(appState: appState)

                DetailPanelView(
                    item: appState.selectedItem,
                    onPaste: { item in
                        pasteAndDismiss(item)
                    },
                    onDelete: { item in
                        appState.deleteItem(item)
                    }
                )
                .frame(width: 220)
            }
            .frame(maxHeight: .infinity)

            FooterView(
                itemCount: appState.totalItemCount,
                statusMessage: appState.statusMessage,
                isAccessibilityGranted: PasteSimulator.isAccessibilityGranted
            )
        }
        .frame(width: 560, height: 456)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: 0xE5E5E5), lineWidth: 1)
        )
        .background(
            KeyEventHandler(
                onArrowUp: { appState.selectPrevious() },
                onArrowDown: { appState.selectNext() },
                onEnter: {
                    if let item = appState.selectedItem {
                        pasteAndDismiss(item)
                    }
                },
                onNumber: { num in
                    let index = num - 1
                    if index >= 0, index < appState.filteredItems.count {
                        let item = appState.filteredItems[index]
                        pasteAndDismiss(item)
                    }
                },
                onTextInput: { chars in
                    // Forward typed characters to search field
                    appState.searchText.append(chars)
                }
            )
        )
        .onExitCommand {
            onDismiss()
        }
    }

    private func pasteAndDismiss(_ item: ClipboardItem) {
        onDismiss()
        // Small delay to let panel hide before pasting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            appState.pasteItem(item)
        }
    }
}

// NSViewRepresentable to capture keyboard events
struct KeyEventHandler: NSViewRepresentable {
    let onArrowUp: () -> Void
    let onArrowDown: () -> Void
    let onEnter: () -> Void
    let onNumber: (Int) -> Void
    let onTextInput: (String) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onArrowUp = onArrowUp
        view.onArrowDown = onArrowDown
        view.onEnter = onEnter
        view.onNumber = onNumber
        view.onTextInput = onTextInput
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onArrowUp = onArrowUp
        nsView.onArrowDown = onArrowDown
        nsView.onEnter = onEnter
        nsView.onNumber = onNumber
        nsView.onTextInput = onTextInput
    }
}

class KeyCaptureView: NSView {
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnter: (() -> Void)?
    var onNumber: ((Int) -> Void)?
    var onTextInput: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            // Cmd+1 through Cmd+9
            if let chars = event.charactersIgnoringModifiers,
               let num = Int(chars), num >= 1, num <= 9 {
                onNumber?(num)
                return
            }
        }

        switch event.keyCode {
        case 126: // Up arrow
            onArrowUp?()
        case 125: // Down arrow
            onArrowDown?()
        case 36: // Return/Enter
            onEnter?()
        default:
            // Forward printable characters to search field
            if let chars = event.characters, !chars.isEmpty,
               !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.control) {
                onTextInput?(chars)
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
```

- [ ] **Step 2: Verify project compiles**

```bash
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PasteFlow/Views/PopoverView.swift
git commit -m "feat: add keyboard navigation — arrows, Enter to paste, Cmd+1-9 shortcuts"
```

---

## Task 13: Integration Test — End-to-End Manual Smoke Test

This task is a manual verification checklist. Run the app and test each feature.

- [ ] **Step 1: Build and run the app**

```bash
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build 2>&1 | tail -3
```

Then open the built app from DerivedData or run from Xcode.

- [ ] **Step 2: Verify menu bar icon**

- App icon appears in the menu bar (not in Dock).
- Clicking shows dropdown: "Open PasteFlow", "Settings...", "Quit PasteFlow".

- [ ] **Step 3: Verify Cmd+Shift+V opens the panel**

- Press Cmd+Shift+V — floating panel appears centered on screen.
- Press Esc — panel dismisses.
- Press Cmd+Shift+V again — panel reappears.

- [ ] **Step 4: Verify clipboard monitoring**

- Copy some text in another app. Open the panel — the copied text should appear in the list.
- Copy a URL — should be tagged as "Link" with the link icon.
- Copy some code from Xcode/VS Code — should be tagged as "Code".
- Take a screenshot (Cmd+Shift+4) — should appear as an image item.

- [ ] **Step 5: Verify search and filters**

- Type in the search bar — list filters to matching items.
- Click filter pills — list filters by type.
- Click "All" — shows everything.

- [ ] **Step 6: Verify keyboard navigation**

- Arrow up/down moves selection.
- Enter pastes the selected item into the previously focused app.
- Cmd+1 through Cmd+9 quick-pastes the Nth item.

- [ ] **Step 7: Verify detail panel**

- Select a text item — preview shows the text.
- Select an image item — preview shows the thumbnail.
- Click "Delete" — item is removed.
- Click "Paste" — item is pasted.

- [ ] **Step 8: Verify Settings**

- Open Settings from menu bar dropdown.
- Change retention period.
- Toggle launch at login.
- "Clear All History" with confirmation.

- [ ] **Step 9: Fix any issues found during testing**

Address bugs discovered during manual testing. Create targeted fixes.

- [ ] **Step 10: Final commit**

```bash
git add -A
git commit -m "fix: address issues from integration testing"
```

---

## Task 14: Update CLAUDE.md and Clean Up

**Files:**
- Modify: `CLAUDE.md`
- Modify: `.gitignore`

- [ ] **Step 1: Update CLAUDE.md with final project structure**

Update `CLAUDE.md` to reflect the actual implemented architecture, dependencies, and project structure.

- [ ] **Step 2: Update .gitignore if needed**

Ensure `.gitignore` covers any new artifacts (e.g., DerivedData, .build).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md .gitignore
git commit -m "docs: update CLAUDE.md with implemented MVP architecture"
```

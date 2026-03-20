import XCTest
@testable import PasteFlow

final class StorageServiceTests: XCTestCase {
    var storage: StorageService!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
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
        let item = ClipboardItem(content: .text("Hello clipboard"), sourceApp: "Safari", contentType: .text)
        try storage.save(item)
        let fetched = try storage.fetchItems(filter: nil, search: nil, limit: 50, offset: 0)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, item.id)
        if case .text(let text) = fetched[0].content {
            XCTAssertEqual(text, "Hello clipboard")
        } else { XCTFail("Expected text content") }
    }

    func testSaveAndFetchImageItem() throws {
        let imageData = Data(repeating: 0xAB, count: 512)
        let item = ClipboardItem(content: .image(imageData, .png), sourceApp: "Preview", contentType: .image)
        try storage.save(item)
        let fetched = try storage.fetchItems(filter: nil, search: nil, limit: 50, offset: 0)
        XCTAssertEqual(fetched.count, 1)
        if case .image(let data, let format) = fetched[0].content {
            XCTAssertEqual(data, imageData)
            XCTAssertEqual(format, .png)
        } else { XCTFail("Expected image content") }
    }

    func testFilterByContentType() throws {
        try storage.save(ClipboardItem(content: .text("text"), sourceApp: nil, contentType: .text))
        try storage.save(ClipboardItem(content: .text("let x = 1"), sourceApp: nil, contentType: .code))
        let textOnly = try storage.fetchItems(filter: .text, search: nil, limit: 50, offset: 0)
        XCTAssertEqual(textOnly.count, 1)
        XCTAssertEqual(textOnly[0].contentType, .text)
        let codeOnly = try storage.fetchItems(filter: .code, search: nil, limit: 50, offset: 0)
        XCTAssertEqual(codeOnly.count, 1)
        XCTAssertEqual(codeOnly[0].contentType, .code)
    }

    func testSearchTextContent() throws {
        try storage.save(ClipboardItem(content: .text("Hello world"), sourceApp: nil, contentType: .text))
        try storage.save(ClipboardItem(content: .text("Goodbye moon"), sourceApp: nil, contentType: .text))
        let results = try storage.fetchItems(filter: nil, search: "Hello", limit: 50, offset: 0)
        XCTAssertEqual(results.count, 1)
    }

    func testDeduplication() throws {
        let item1 = ClipboardItem(content: .text("duplicate"), sourceApp: nil, contentType: .text)
        try storage.save(item1)
        let item2 = ClipboardItem(content: .text("duplicate"), sourceApp: nil, contentType: .text)
        try storage.save(item2)
        let fetched = try storage.fetchItems(filter: nil, search: nil, limit: 50, offset: 0)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, item2.id)
    }

    func testDeleteItem() throws {
        let item = ClipboardItem(content: .text("to delete"), sourceApp: nil, contentType: .text)
        try storage.save(item)
        try storage.delete(item.id)
        let fetched = try storage.fetchItems(filter: nil, search: nil, limit: 50, offset: 0)
        XCTAssertEqual(fetched.count, 0)
    }

    func testDeleteExpired() throws {
        let oldItem = ClipboardItem(id: UUID(), content: .text("old"), sourceApp: nil,
            createdAt: Date().addingTimeInterval(-31 * 24 * 3600), contentType: .text)
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
        let item1 = ClipboardItem(id: UUID(), content: .text("first"), sourceApp: nil,
            createdAt: Date().addingTimeInterval(-100), contentType: .text)
        let item2 = ClipboardItem(id: UUID(), content: .text("second"), sourceApp: nil,
            createdAt: Date().addingTimeInterval(-50), contentType: .text)
        let item3 = ClipboardItem(content: .text("third"), sourceApp: nil, contentType: .text)
        try storage.save(item1)
        try storage.save(item2)
        try storage.save(item3)
        let page1 = try storage.fetchItems(filter: nil, search: nil, limit: 2, offset: 0)
        XCTAssertEqual(page1.count, 2)
        XCTAssertEqual(page1[0].id, item3.id)
        XCTAssertEqual(page1[1].id, item2.id)
        let page2 = try storage.fetchItems(filter: nil, search: nil, limit: 2, offset: 2)
        XCTAssertEqual(page2.count, 1)
        XCTAssertEqual(page2[0].id, item1.id)
    }

    func testDeleteImageRemovesFile() throws {
        let imageData = Data(repeating: 0xCD, count: 256)
        let item = ClipboardItem(content: .image(imageData, .png), sourceApp: nil, contentType: .image)
        try storage.save(item)
        let imagePath = tempDir.appendingPathComponent("images").appendingPathComponent("\(item.id.uuidString).png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagePath.path))
        try storage.delete(item.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imagePath.path))
    }
}

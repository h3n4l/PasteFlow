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

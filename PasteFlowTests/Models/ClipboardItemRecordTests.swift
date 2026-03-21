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

    func testFileItemCreation() {
        let refs = [
            FileReference(path: "/Users/test/doc.pdf", name: "doc.pdf", size: 204800,
                           utiType: "com.adobe.pdf", utiDescription: "PDF Document")
        ]
        let item = ClipboardItem(content: .file(refs), sourceApp: "Finder", contentType: .file)
        XCTAssertNil(item.characterCount)
        XCTAssertNil(item.imageSize)
        XCTAssertEqual(item.contentType, .file)
        XCTAssertFalse(item.contentHash.isEmpty)
    }

    func testFileItemHashIgnoresOrder() {
        let ref1 = FileReference(path: "/a.txt", name: "a.txt", size: 100,
                                  utiType: "public.plain-text", utiDescription: "Text")
        let ref2 = FileReference(path: "/b.txt", name: "b.txt", size: 200,
                                  utiType: "public.plain-text", utiDescription: "Text")
        let item1 = ClipboardItem(content: .file([ref1, ref2]), sourceApp: nil, contentType: .file)
        let item2 = ClipboardItem(content: .file([ref2, ref1]), sourceApp: nil, contentType: .file)
        XCTAssertEqual(item1.contentHash, item2.contentHash)
    }

    func testFileReferenceJsonRoundtrip() throws {
        let ref = FileReference(path: "/Users/test/doc.pdf", name: "doc.pdf", size: 204800,
                                 utiType: "com.adobe.pdf", utiDescription: "PDF Document")
        let data = try JSONEncoder().encode([ref])
        let decoded = try JSONDecoder().decode([FileReference].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0], ref)
    }
}

import XCTest
@testable import PasteFlow

final class ContentClassifierTests: XCTestCase {
    func testPlainTextClassification() {
        XCTAssertEqual(ContentClassifier.classify("Hello, world!"), .text)
        XCTAssertEqual(ContentClassifier.classify("Meeting notes from today"), .text)
    }
    func testURLClassification() {
        XCTAssertEqual(ContentClassifier.classify("https://github.com/h3n4l/PasteFlow"), .link)
        XCTAssertEqual(ContentClassifier.classify("http://example.com"), .link)
    }
    func testCodeClassification() {
        XCTAssertEqual(ContentClassifier.classify("let x = 42\nvar y = x + 1"), .code)
        XCTAssertEqual(ContentClassifier.classify("func hello() {\n    print(\"hi\")\n}"), .code)
        XCTAssertEqual(ContentClassifier.classify("import Foundation\nclass Foo {}"), .code)
    }
    func testCodeTakesPriorityOverLink() {
        let codeWithURL = "let url = \"https://api.example.com/v1\"\nlet request = URLRequest(url: url)"
        XCTAssertEqual(ContentClassifier.classify(codeWithURL), .code)
    }
    func testSingleKeywordIsNotCode() {
        XCTAssertEqual(ContentClassifier.classify("let me know if this works"), .text)
    }
    func testEmptyStringIsText() {
        XCTAssertEqual(ContentClassifier.classify(""), .text)
    }
}

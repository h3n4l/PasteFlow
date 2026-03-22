import XCTest
@testable import PasteFlow

final class AppearanceModeTests: XCTestCase {
    func testRawValues() {
        XCTAssertEqual(AppearanceMode.system.rawValue, "system")
        XCTAssertEqual(AppearanceMode.light.rawValue, "light")
        XCTAssertEqual(AppearanceMode.dark.rawValue, "dark")
    }

    func testCaseIterable() {
        XCTAssertEqual(AppearanceMode.allCases.count, 3)
    }

    func testDisplayName() {
        XCTAssertEqual(AppearanceMode.system.displayName, "System")
        XCTAssertEqual(AppearanceMode.light.displayName, "Light")
        XCTAssertEqual(AppearanceMode.dark.displayName, "Dark")
    }

    func testInitFromRawValue() {
        XCTAssertEqual(AppearanceMode(rawValue: "system"), .system)
        XCTAssertEqual(AppearanceMode(rawValue: "light"), .light)
        XCTAssertEqual(AppearanceMode(rawValue: "dark"), .dark)
        XCTAssertNil(AppearanceMode(rawValue: "invalid"))
    }
}

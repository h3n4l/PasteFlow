import XCTest
@testable import PasteFlow

final class AppStateTests: XCTestCase {
    var tempDir: URL!
    var state: AppState!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storage = try! StorageService(
            databasePath: tempDir.appendingPathComponent("test.db").path,
            imagesDirectory: tempDir.appendingPathComponent("images")
        )
        for (index, text) in ["first", "second", "third"].enumerated() {
            try! storage.save(ClipboardItem(
                content: .text(text), sourceApp: nil,
                createdAt: Date().addingTimeInterval(-Double(index) * 60), contentType: .text
            ))
        }
        state = AppState(storage: storage)
    }

    override func tearDown() {
        state = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testDeletingSelectedItemSelectsTheItemThatTakesItsPlace() {
        let items = state.clipboardItems
        XCTAssertEqual(items.count, 3)
        state.select(items[1])

        state.deleteItem(items[1])

        XCTAssertEqual(state.clipboardItems.map(\.id), [items[0].id, items[2].id])
        XCTAssertEqual(state.selectedItem?.id, items[2].id)
        XCTAssertEqual(state.totalItemCount, 2)
    }

    func testDeletingLastItemSelectsTheOneBeforeIt() {
        let items = state.clipboardItems
        state.select(items[2])

        state.deleteItem(items[2])

        XCTAssertEqual(state.selectedItem?.id, items[1].id)
    }

    func testDeletingTheOnlyItemClearsTheSelection() {
        let items = state.clipboardItems
        state.deleteItem(items[0])
        state.deleteItem(items[1])

        state.deleteItem(items[2])

        XCTAssertTrue(state.clipboardItems.isEmpty)
        XCTAssertNil(state.selectedItem)
        XCTAssertEqual(state.totalItemCount, 0)
    }

    func testDeletingLoadsAnItemInPlaceOfTheDeletedOne() throws {
        // More than one page (50) in total: 3 from setUp and 60 older ones.
        for index in 0..<60 {
            try state.storage.save(ClipboardItem(
                content: .text("older \(index)"), sourceApp: nil,
                createdAt: Date().addingTimeInterval(-3600 - Double(index) * 60), contentType: .text
            ))
        }
        state.reloadItems()
        XCTAssertEqual(state.clipboardItems.count, 50)
        XCTAssertEqual(state.totalItemCount, 63)

        // Deleting from the top never scrolls to the row that loads the next page.
        for _ in 0..<55 {
            state.deleteItem(state.clipboardItems[0])
        }

        XCTAssertEqual(state.totalItemCount, 8)
        XCTAssertEqual(state.clipboardItems.count, 8)
        XCTAssertEqual(Set(state.clipboardItems.map(\.id)).count, 8)
    }

    func testOnlyUserMovesCountAsSelectionMoves() {
        let moves = state.selectionMoves

        state.selectNext()
        XCTAssertEqual(state.selectionMoves, moves + 1)

        // Already on this item, and a reload: neither is the user moving the selection.
        state.select(state.clipboardItems[1])
        state.reloadItems()
        XCTAssertEqual(state.selectionMoves, moves + 1)

        // At the end of the list there is nowhere further to go.
        state.selectNext()
        state.selectNext()
        XCTAssertEqual(state.selectionMoves, moves + 2)
    }

    func testOnlyChangesTheUserCausedCountAsListChanges() {
        let changes = state.listChanges

        state.reloadItems()
        XCTAssertEqual(state.listChanges, changes)

        state.setFilter(.code)
        XCTAssertEqual(state.listChanges, changes + 1)

        state.setFilter(nil)
        state.deleteItem(state.clipboardItems[0])
        XCTAssertEqual(state.listChanges, changes + 3)
    }
}

import XCTest
import AppKit
@testable import ClipbookCore

final class MultiSelectTests: XCTestCase {
    // MARK: Selection

    func testShiftArrowsExtendARangeInReadingOrder() {
        var nav = GridNavigation(columns: 8, count: 40)
        nav.extend(.right); nav.extend(.right)
        XCTAssertEqual(nav.selection, [0, 1, 2])
        nav.extend(.down)                                   // a whole row more
        XCTAssertEqual(nav.selection, Set(0...10))
        nav.extend(.up); nav.extend(.left)                  // shrinks back toward the start
        XCTAssertEqual(nav.selection, [0, 1])
        XCTAssertTrue(nav.isMultiSelecting)
    }

    func testRangeCanGrowBackwardsFromTheStart() {
        var nav = GridNavigation(columns: 8, count: 40)
        nav.move(.down); nav.move(.right)                   // cursor on 9
        nav.extend(.left); nav.extend(.left)
        XCTAssertEqual(nav.selection, [7, 8, 9])
    }

    func testPlainArrowClickOrClampClearsTheSelection() {
        var nav = GridNavigation(columns: 8, count: 40)
        nav.extend(.right); nav.extend(.right)
        nav.move(.right)
        XCTAssertEqual(nav.selection, [3])
        nav.extend(.right)
        nav.select(20)
        XCTAssertEqual(nav.selection, [20])
        nav.extend(.right)
        nav.clampToCount()
        XCTAssertFalse(nav.isMultiSelecting)
    }

    func testShiftClickAndCommandClick() {
        var nav = GridNavigation(columns: 8, count: 40)
        nav.select(2)
        nav.extend(to: 5)
        XCTAssertEqual(nav.selection, [2, 3, 4, 5])
        nav.toggle(12)                                      // add a tile elsewhere
        XCTAssertEqual(nav.selection, [2, 3, 4, 5, 12])
        nav.toggle(3)                                       // and drop one
        XCTAssertEqual(nav.selection, [2, 4, 5, 12])
        XCTAssertEqual(nav.selected, 3, "the cursor follows the click")
    }

    func testSingleTileIsNotAMultiSelection() {
        let nav = GridNavigation(count: 5)
        XCTAssertEqual(nav.selection, [0])
        XCTAssertFalse(nav.isMultiSelecting)
    }

    // MARK: Clipboard contents

    private func item(_ id: Int64, _ payload: ClipPayload, at t: TimeInterval) -> ClipItem {
        ClipItem(id: id, payload: payload, createdAt: Date(timeIntervalSince1970: t))
    }

    func testCopiesOldestFirstWhateverTheSelectionOrder() {
        let grid = [item(3, .text("third"), at: 30), item(1, .text("first"), at: 10), item(2, .text("second"), at: 20)]
        XCTAssertEqual(MultiCopy.chronological(grid).map(\.id), [1, 2, 3])
    }

    func testAllTextBecomesOneBlock() {
        let items = MultiCopy.pasteboardItems(for: [item(2, .text("b"), at: 2), item(1, .text("a"), at: 1)])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].string(forType: .string), "a\nb")
    }

    func testImagesCarryDataAndANumberedFileInOrder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clipbook-multicopy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let older = Data([1, 2, 3]), newer = Data([4, 5, 6])
        let items = MultiCopy.pasteboardItems(
            for: [item(9, .image(newer), at: 90), item(8, .image(older), at: 80), item(7, .text("note"), at: 70)],
            fileDirectory: dir)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].string(forType: .string), "note")
        XCTAssertEqual(items[1].data(forType: .png), older)
        XCTAssertEqual(items[2].data(forType: .png), newer)
        let firstFile = try XCTUnwrap(URL(string: try XCTUnwrap(items[1].string(forType: .fileURL))))
        XCTAssertEqual(firstFile.lastPathComponent, "Clipbook 01.png")
        XCTAssertEqual(try Data(contentsOf: firstFile), older)
    }
}

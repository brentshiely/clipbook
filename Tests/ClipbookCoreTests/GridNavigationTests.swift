import XCTest
@testable import ClipbookCore

final class GridNavigationTests: XCTestCase {
    func testDefaultGridIsEightColumnsByThreeRows() {
        var nav = GridNavigation(count: 100)
        XCTAssertEqual(nav.columns, 8)
        XCTAssertEqual(GridNavigation.visibleRows, 3)
        nav.move(.down)
        XCTAssertEqual(nav.selected, 8)     // down moves exactly one 8-wide row
    }

    func testStartsOnNewestTile() {
        XCTAssertEqual(GridNavigation(count: 5).selected, 0)
    }

    func testRightWrapsToNextRowAndStopsAtEnd() {
        var nav = GridNavigation(columns: 10, count: 12)
        for _ in 0..<10 { nav.move(.right) }
        XCTAssertEqual(nav.selected, 10)
        XCTAssertEqual(nav.row, 1)
        XCTAssertEqual(nav.column, 0)
        nav.move(.right); nav.move(.right); nav.move(.right)
        XCTAssertEqual(nav.selected, 11)
    }

    func testLeftWrapsToPreviousRowAndStopsAtStart() {
        var nav = GridNavigation(columns: 10, count: 30)
        nav.move(.left)
        XCTAssertEqual(nav.selected, 0)
        for _ in 0..<10 { nav.move(.right) }
        nav.move(.left)
        XCTAssertEqual(nav.selected, 9)
    }

    func testDownAndUpMoveOneFullRow() {
        var nav = GridNavigation(columns: 10, count: 100)
        nav.move(.right); nav.move(.right)   // column 2
        nav.move(.down)
        XCTAssertEqual(nav.selected, 12)
        nav.move(.down)
        XCTAssertEqual(nav.selected, 22)
        nav.move(.up)
        XCTAssertEqual(nav.selected, 12)
        nav.move(.up); nav.move(.up)
        XCTAssertEqual(nav.selected, 2)     // stays in top row
    }

    func testDownIntoShortLastRowLandsOnLastTile() {
        var nav = GridNavigation(columns: 10, count: 13)
        for _ in 0..<8 { nav.move(.right) }  // column 8
        nav.move(.down)
        XCTAssertEqual(nav.selected, 12)
        nav.move(.down)                      // already on last row
        XCTAssertEqual(nav.selected, 12)
    }

    func testEmptyGridIgnoresMoves() {
        var nav = GridNavigation(count: 0)
        for d in [GridMove.left, .right, .up, .down] { nav.move(d) }
        XCTAssertEqual(nav.selected, 0)
    }

    func testNearEndTriggersPaging() {
        var nav = GridNavigation(columns: 10, count: 200)   // 20 rows
        XCTAssertFalse(nav.isNearEnd())
        for _ in 0..<16 { nav.move(.down) }                 // row 16
        XCTAssertTrue(nav.isNearEnd())
    }
}

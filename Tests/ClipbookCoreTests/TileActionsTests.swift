import XCTest
@testable import ClipbookCore

final class TileActionsTests: XCTestCase {
    func testImageTileOffersSave() {
        let tip = TileActions.tooltip(for: .image(Data([0])))
        XCTAssertTrue(tip.contains("⌘S"))
        XCTAssertTrue(tip.contains("Paste"))
    }

    func testVideoTileOffersPlayButNotSave() {
        let tip = TileActions.tooltip(for: .video(path: "/tmp/a.mov", thumbnail: Data([0])))
        XCTAssertTrue(tip.contains("space"))
        XCTAssertFalse(tip.contains("⌘S"))
    }

    func testEveryTileCanBePastedAndDeleted() {
        for payload: ClipPayload in [.text("x"), .files(["/tmp/a"]), .image(Data([0]))] {
            let keys = TileActions.actions(for: payload).map(\.title)
            XCTAssertTrue(keys.contains("Paste") && keys.contains("Delete"))
        }
    }
}

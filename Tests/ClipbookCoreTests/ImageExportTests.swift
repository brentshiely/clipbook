import XCTest
@testable import ClipbookCore

final class ImageExportTests: XCTestCase {
    func testSavesPNGBytesAndNeverOverwrites() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clipbook-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let a = try ImageExport.save(png: Data([1, 2, 3]), to: dir, date: date)
        let b = try ImageExport.save(png: Data([4, 5, 6]), to: dir, date: date)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: a), Data([1, 2, 3]))
        XCTAssertEqual(try Data(contentsOf: b), Data([4, 5, 6]))
    }
}

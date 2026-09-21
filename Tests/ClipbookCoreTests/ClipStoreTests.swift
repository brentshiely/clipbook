import XCTest
import AppKit
@testable import ClipbookCore

final class ClipStoreTests: XCTestCase {
    private func makeStore() throws -> ClipStore {
        let path = NSTemporaryDirectory() + "clipbook-test-\(UUID().uuidString).sqlite"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return try ClipStore(path: path)
    }

    func testFetchIsNewestFirst() throws {
        let store = try makeStore()
        try store.insert(.text("one"), at: Date(timeIntervalSince1970: 1))
        try store.insert(.text("two"), at: Date(timeIntervalSince1970: 2))
        try store.insert(.text("three"), at: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(try store.fetch(limit: 10).map(\.payload), [.text("three"), .text("two"), .text("one")])
    }

    func testConsecutiveDuplicatesCollapseButNonConsecutiveDoNot() throws {
        let store = try makeStore()
        XCTAssertNotNil(try store.insert(.text("a"), at: Date(timeIntervalSince1970: 1)))
        XCTAssertNil(try store.insert(.text("a"), at: Date(timeIntervalSince1970: 2)))
        try store.insert(.text("b"), at: Date(timeIntervalSince1970: 3))
        XCTAssertNotNil(try store.insert(.text("a"), at: Date(timeIntervalSince1970: 4)))
        XCTAssertEqual(try store.count(), 3)
    }

    func testPagingBeyondFirstHundred() throws {
        let store = try makeStore()
        for i in 0..<250 { try store.insert(.text("item \(i)"), at: Date(timeIntervalSince1970: Double(i))) }
        let page = try store.fetch(limit: 100, offset: 100)
        XCTAssertEqual(page.count, 100)
        XCTAssertEqual(page.first?.payload, .text("item 149"))
        XCTAssertEqual(try store.fetch(limit: 100, offset: 200).count, 50)
    }

    func testAllPayloadKindsRoundTrip() throws {
        let store = try makeStore()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF])
        try store.insert(.text("hello\nworld"), at: Date(timeIntervalSince1970: 1))
        try store.insert(.image(png), at: Date(timeIntervalSince1970: 2))
        try store.insert(.files(["/tmp/a.txt", "/tmp/b.txt"]), at: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(try store.fetch(limit: 10).map(\.payload),
                       [.files(["/tmp/a.txt", "/tmp/b.txt"]), .image(png), .text("hello\nworld")])
    }

    func testClearEmptiesHistory() throws {
        let store = try makeStore()
        try store.insert(.text("x"))
        try store.clear()
        XCTAssertEqual(try store.count(), 0)
        XCTAssertNotNil(try store.insert(.text("x")))   // dedupe state is cleared too
    }

    func testWatcherCapturesTextAndSkipsConcealed() {
        let pb = NSPasteboard(name: NSPasteboard.Name("clipbook-test-\(UUID().uuidString)"))
        var captured: [ClipPayload] = []
        let watcher = PasteboardWatcher(pasteboard: pb) { payload, _ in captured.append(payload) }

        pb.clearContents()
        pb.setString("copied text", forType: .string)
        watcher.poll()

        pb.clearContents()
        pb.setString("hunter2", forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        watcher.poll()

        XCTAssertEqual(captured, [.text("copied text")])
    }
}

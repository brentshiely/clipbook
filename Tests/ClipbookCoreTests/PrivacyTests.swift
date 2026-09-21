import XCTest
import AppKit
@testable import ClipbookCore

final class PrivacyTests: XCTestCase {
    func testRecognizesPasswordManagerApps() {
        for id in ["com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "org.keepassxc.keepassxc",
                   "com.apple.Passwords", "com.apple.keychainaccess", "com.dashlane.dashlanephonefinal", "me.proton.pass.electron"] {
            XCTAssertTrue(SensitiveSource.isPasswordManager(bundleID: id), id)
        }
        for id in ["com.google.Chrome", "com.apple.Safari", "com.apple.dt.Xcode", "com.tinyspeck.slackmacgap", "", nil] as [String?] {
            XCTAssertFalse(SensitiveSource.isPasswordManager(bundleID: id), id ?? "nil")
        }
    }

    private func makeWatcher(front: @escaping () -> String?, into captured: @escaping (ClipPayload) -> Void)
        -> (PasteboardWatcher, NSPasteboard) {
        let pb = NSPasteboard(name: NSPasteboard.Name("clipbook-test-\(UUID().uuidString)"))
        return (PasteboardWatcher(pasteboard: pb, frontmostBundleID: front) { payload, _ in captured(payload) }, pb)
    }

    func testCopyMadeInPasswordManagerIsNeverCaptured_evenWithoutAFlag() {
        var captured: [ClipPayload] = []
        var front: String? = "com.1password.1password"
        let (watcher, pb) = makeWatcher(front: { front }, into: { captured.append($0) })

        pb.clearContents(); pb.setString("Tr0ub4dor&3", forType: .string)      // no concealed flag at all
        watcher.poll()
        XCTAssertTrue(captured.isEmpty)

        // Switching to another app right after copying still doesn't let it through.
        pb.clearContents(); pb.setString("another-secret", forType: .string)
        front = "com.apple.Safari"
        watcher.poll()
        XCTAssertTrue(captured.isEmpty)

        // Ordinary copies from ordinary apps are kept again on the following polls.
        pb.clearContents(); pb.setString("hello", forType: .string)
        watcher.poll()
        XCTAssertEqual(captured, [.text("hello")])
    }

    func testLegacyManagerPasteboardTypesAreSkipped() {
        var captured: [ClipPayload] = []
        let (watcher, pb) = makeWatcher(front: { "com.apple.Safari" }, into: { captured.append($0) })
        pb.clearContents()
        pb.setString("secret", forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType("com.agilebits.onepassword"))
        watcher.poll()
        XCTAssertTrue(captured.isEmpty)
    }

    func testDeleteRemovesTheItemAndOverwritesItsBytesOnDisk() throws {
        let path = NSTemporaryDirectory() + "clipbook-test-\(UUID().uuidString).sqlite"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        let secret = "ZX-PRIVATE-9931-marker"
        do {
            let store = try ClipStore(path: path)
            try store.insert(.text("keep me"), at: Date(timeIntervalSince1970: 1))
            let inserted = try XCTUnwrap(try store.insert(.text(secret), at: Date(timeIntervalSince1970: 2)))
            try store.delete(id: inserted.id)
            XCTAssertEqual(try store.fetch(limit: 10).map(\.payload), [.text("keep me")])
        }   // store closed: now inspect the raw file
        let raw = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertNil(raw.range(of: Data(secret.utf8)), "deleted text must not remain in the database file")
    }

    func testSelectionStaysValidAfterDeletingTheLastTile() {
        var nav = GridNavigation(columns: 8, count: 10)
        nav.move(.down); nav.move(.right)     // second row, second tile: the last one (index 9)
        XCTAssertEqual(nav.selected, 9)
        nav.count = 9
        nav.clampToCount()
        XCTAssertEqual(nav.selected, 8)
        nav.count = 0
        nav.clampToCount()
        XCTAssertEqual(nav.selected, 0)
    }
}

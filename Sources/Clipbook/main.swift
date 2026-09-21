import AppKit
import SwiftUI
import ClipbookCore

MainActor.assumeIsolated {
    let args = CommandLine.arguments

    // `Clipbook --snapshot out.png` renders the grid over seeded sample data (for layout checks).
    if let flag = args.firstIndex(of: "--snapshot"), args.indices.contains(flag + 1) {
        renderSnapshot(to: args[flag + 1], rows: args.contains("--long") ? 14 : 10)
        exit(0)
    }

    let store = try! ClipStore(path: ClipStore.defaultPath())
    let app = NSApplication.shared
    let delegate = AppDelegate(store: store)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

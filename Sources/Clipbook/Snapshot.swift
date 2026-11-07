import AppKit
import SwiftUI
import ClipbookCore

private func sampleScreenshotPNG(hue: CGFloat) -> Data? {
    let size = NSSize(width: 1600, height: 1000)          // screen-shaped, to check nothing gets cropped
    let img = NSImage(size: size, flipped: false) { rect in
        NSColor(hue: hue, saturation: 0.35, brightness: 0.25, alpha: 1).setFill()
        rect.fill()
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSRect(x: 0, y: rect.height - 50, width: rect.width, height: 50).fill()          // menu bar
        NSRect(x: 60, y: 120, width: 700, height: 700).fill()                              // a window
        NSColor.systemRed.setFill()
        NSRect(x: rect.width - 90, y: 20, width: 60, height: 60).fill()                    // corner marker
        return true
    }
    guard let tiff = img.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
}

@MainActor
func renderSnapshot(to path: String, rows: Int, multiSelect: Bool = false) {
    let dbPath = NSTemporaryDirectory() + "clipbook-snapshot-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let store = try! ClipStore(path: dbPath)

    let samples = ["Hello, world", "https://example.com/some/long/url?with=params", "TODO: call the dentist",
                   "func greet() {\n  print(\"hi\")\n}", "Meeting notes: Q3 planning, budget review, hiring plan",
                   "42", "Photograph", "Buy oat milk, eggs, and coffee filters on the way home from the office tonight",
                   "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."]
    let total = rows * GridNavigation.defaultColumns + 16      // more than a screenful, to show the footer
    for i in 0..<total {
        let date = Date(timeIntervalSince1970: Double(i))
        if i == total - 1 { try? store.insert(.text("Cat"), at: date); continue }          // newest: selected tile
        switch i % 7 {
        case 3:
            if let png = sampleScreenshotPNG(hue: CGFloat(i % 5) / 5) { try? store.insert(.image(png), at: date) }
        case 5:
            if let png = sampleScreenshotPNG(hue: CGFloat(i % 5) / 5) { try? store.insert(.video(path: "/tmp/sample.mov", thumbnail: png), at: date) }
        default: try? store.insert(.text("\(samples[i % samples.count])"), at: date)
        }
    }

    let model = ClipbookViewModel(store: store)
    model.reload()
    if multiSelect {                       // ⇧→ ⇧→ ⇧↓: tiles 0–10, as the keyboard would
        for (code, flags) in [(124, NSEvent.ModifierFlags.shift), (124, .shift), (125, .shift)] {
            _ = model.handleKey(keyCode: UInt16(code), modifiers: flags)
        }
    }
    let tile = ClipbookPanelController.tileSize(for: NSScreen.main)
    let view = ClipbookView(model: model, tileSize: tile)
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(Int(host.bounds.width))x\(Int(host.bounds.height)), tile \(Int(tile)))")
}

/// `Clipbook --snapshot-markup panel.png result.png`: opens the editor on a sample screenshot, draws a
/// rectangle, an arrow and text through the same calls the mouse and keyboard make, and renders both
/// the editor and the saved image.
@MainActor
func renderMarkupSnapshot(to path: String, result: String) {
    let dbPath = NSTemporaryDirectory() + "clipbook-snapshot-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let store = try! ClipStore(path: dbPath)
    guard let png = sampleScreenshotPNG(hue: 0.6) else { exit(1) }
    _ = try? store.insert(.image(png), at: Date(timeIntervalSince1970: 1))
    let model = ClipbookViewModel(store: store)
    model.reload()
    model.startMarkup()
    guard let size = model.markup?.imageSize else { print("markup did not start"); exit(1) }
    let w = size.width, h = size.height
    model.markup?.endDrag(from: CGPoint(x: w * 0.04, y: h * 0.12), to: CGPoint(x: w * 0.48, y: h * 0.86), tolerance: 8)
    model.markup?.tool = .arrow
    model.markup?.endDrag(from: CGPoint(x: w * 0.8, y: h * 0.35), to: CGPoint(x: w * 0.93, y: h * 0.86), tolerance: 8)
    _ = model.handleKey(keyCode: 17, modifiers: [], characters: "t")
    model.markup?.click(at: CGPoint(x: w * 0.55, y: h * 0.25), tolerance: 8)
    for ch in "Look here" { _ = model.handleKey(keyCode: 0, modifiers: [], characters: String(ch)) }

    let tile = ClipbookPanelController.tileSize(for: NSScreen.main)
    let host = NSHostingView(rootView: ClipbookView(model: model, tileSize: tile))
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.contentView = host
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    let marks = model.markup?.marks.count ?? 0
    var saved: Data?
    model.onCopyImage = { saved = $0 }
    _ = model.handleKey(keyCode: 36, modifiers: [], characters: "\r")     // ↩ ends the text
    _ = model.handleKey(keyCode: 36, modifiers: [], characters: "\r")     // ↩ saves
    try? saved?.write(to: URL(fileURLWithPath: result))
    let newest = model.items.first.map { item -> String in
        if case .image(let d) = item.payload { return d == saved ? "the marked-up image" : "a different image" }
        return "not an image"
    } ?? "nothing"
    print("marks=\(marks) editorOpen=\(model.markup != nil) items=\(model.items.count) newest=\(newest) wrote \(path) and \(result)")
}

/// `Clipbook --snapshot-play out.png video.mov`: opens the in-panel player on a real file and renders it.
@MainActor
func renderPlayerSnapshot(to path: String, video: String) {
    let dbPath = NSTemporaryDirectory() + "clipbook-snapshot-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let store = try! ClipStore(path: dbPath)
    _ = try? store.insert(.text("Hello, world"), at: Date(timeIntervalSince1970: 1))
    if let png = sampleScreenshotPNG(hue: 0.6) {
        _ = try? store.insert(.video(path: video, thumbnail: png), at: Date(timeIntervalSince1970: 2))
    }
    let model = ClipbookViewModel(store: store)
    model.reload()
    model.playSelected()
    let tile = ClipbookPanelController.tileSize(for: NSScreen.main)
    let host = NSHostingView(rootView: ClipbookView(model: model, tileSize: tile))
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.contentView = host
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(2))      // let the player load a frame
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    if let p = model.player, let item = p.currentItem {
        print("status=\(item.status.rawValue) rate=\(p.rate) time=\(String(format: "%.2f", p.currentTime().seconds)) size=\(item.presentationSize)")
    }
    print("playing=\(model.player != nil) error=\(model.playbackError ?? "none") wrote \(path)")
}

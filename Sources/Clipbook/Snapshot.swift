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
func renderSnapshot(to path: String, rows: Int) {
    let dbPath = NSTemporaryDirectory() + "clipbook-snapshot-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let store = try! ClipStore(path: dbPath)

    let samples = ["Hello, world", "https://example.com/some/long/url?with=params", "TODO: call the dentist",
                   "func greet() {\n  print(\"hi\")\n}", "Meeting notes: Q3 planning, budget review, hiring plan",
                   "42", "Photograph", "Buy oat milk, eggs, and coffee filters on the way home from the office tonight",
                   "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."]
    let total = rows * GridNavigation.defaultColumns
    for i in 0..<total {
        let date = Date(timeIntervalSince1970: Double(i))
        if i == total - 1 { try? store.insert(.text("Cat"), at: date); continue }          // newest: selected tile
        switch i % 7 {
        case 3:
            if let png = sampleScreenshotPNG(hue: CGFloat(i % 5) / 5) { try? store.insert(.image(png), at: date) }
        case 5: try? store.insert(.files(["/Applications/Safari.app"]), at: date)
        default: try? store.insert(.text("\(samples[i % samples.count])"), at: date)
        }
    }

    let model = ClipbookViewModel(store: store)
    model.reload()
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

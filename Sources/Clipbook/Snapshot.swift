import AppKit
import SwiftUI
import ClipbookCore

@MainActor
func renderSnapshot(to path: String, rows: Int) {
    let dbPath = NSTemporaryDirectory() + "clipbook-snapshot-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let store = try! ClipStore(path: dbPath)

    let samples = ["Hello, world", "https://example.com/some/long/url?with=params", "TODO: call the dentist",
                   "func greet() {\n  print(\"hi\")\n}", "Meeting notes: Q3 planning, budget review, hiring", "42"]
    for i in 0..<(rows * 10 - 3) {
        let date = Date(timeIntervalSince1970: Double(i))
        switch i % 9 {
        case 4:
            let img = NSImage(size: NSSize(width: 200, height: 120), flipped: false) { rect in
                NSColor(hue: CGFloat(i % 7) / 7, saturation: 0.6, brightness: 0.9, alpha: 1).setFill()
                rect.fill()
                return true
            }
            if let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? store.insert(.image(png), at: date)
            }
        case 7: try? store.insert(.files(["/Applications/Safari.app"]), at: date)
        default: try? store.insert(.text("\(samples[i % samples.count]) #\(i)"), at: date)
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

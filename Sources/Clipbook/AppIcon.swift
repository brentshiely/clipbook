import AppKit

/// Draws the app icon (a dark rounded square holding a grid of tiles, top-left one selected) as a 1024 px PNG.
/// `Clipbook --icon out.png` calls this; scripts/build-app.sh turns it into AppIcon.icns.
func renderAppIcon(to path: String) {
    let px = 1024
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
    NSGraphicsContext.current = ctx

    // macOS icon grid: an 824 pt rounded square centred in the 1024 canvas.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGradient(colors: [NSColor(white: 0.24, alpha: 1), NSColor(white: 0.10, alpha: 1)])!.draw(in: bodyPath, angle: -90)

    // 4 x 3 tiles, like the real grid.
    let cols = 4, rows = 3
    let tile: CGFloat = 148, gap: CGFloat = 26
    let gridW = CGFloat(cols) * tile + CGFloat(cols - 1) * gap
    let gridH = CGFloat(rows) * tile + CGFloat(rows - 1) * gap
    let originX = body.midX - gridW / 2
    let originY = body.midY - gridH / 2
    let tones: [CGFloat] = [0.92, 0.70, 0.84, 0.62, 0.78, 0.94, 0.66, 0.88, 0.72, 0.90, 0.60, 0.80]

    for row in 0..<rows {
        for col in 0..<cols {
            let index = row * cols + col
            let x = originX + CGFloat(col) * (tile + gap)
            let y = originY + CGFloat(rows - 1 - row) * (tile + gap)     // row 0 is the top row
            let rect = NSRect(x: x, y: y, width: tile, height: tile)
            let shape = NSBezierPath(roundedRect: rect, xRadius: 30, yRadius: 30)
            if index == 0 {
                NSColor.systemBlue.setFill()
                shape.fill()
                NSColor.white.setStroke()
                shape.lineWidth = 8
                shape.stroke()
            } else {
                NSColor(white: tones[index], alpha: 1).setFill()
                shape.fill()
            }
        }
    }
    NSGraphicsContext.current = nil
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

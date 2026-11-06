import SwiftUI
import ClipbookCore

/// Fills the panel while an image is being marked up. Drag draws with the current tool, a click
/// selects (or places text with T); everything else is on the keyboard, handled by the view model.
struct MarkupEditorView: View {
    @ObservedObject var model: ClipbookViewModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .windowBackgroundColor))
            VStack(spacing: 10) {
                toolbar
                if let session = model.markup, let image = model.markupImage {
                    GeometryReader { geo in canvas(session: session, image: image, box: geo.size) }
                }
            }
            .padding(16)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("Mark up").font(.headline)
            toolButton("R", "Rectangle", "rectangle", .rectangle)
            toolButton("A", "Arrow", "arrow.up.right", .arrow)
            toolButton("T", "Text", "textformat", .text)
            Spacer()
            Text(model.markup?.typing != nil
                 ? "type your text   ↩ or esc done"
                 : "drag to draw   click to select   ←↑↓→ nudge   ⌫ delete   ⌘Z undo   ↩ done   esc cancel")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func toolButton(_ key: String, _ title: String, _ symbol: String, _ tool: MarkTool) -> some View {
        let active = model.markup?.tool == tool
        return Button { model.markup?.tool = tool } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title)
                Text(key).font(.caption.monospaced()).opacity(0.7)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(active ? Color.red : Color.primary.opacity(0.08)))
            .foregroundStyle(active ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    /// The image, scaled to fit, with the marks drawn over it by the same renderer that saves the PNG.
    private func canvas(session: MarkupSession, image: NSImage, box: CGSize) -> some View {
        let px = session.imageSize
        let scale = min(box.width / px.width, box.height / px.height)
        let shown = CGSize(width: px.width * scale, height: px.height * scale)
        let origin = CGPoint(x: (box.width - shown.width) / 2, y: (box.height - shown.height) / 2)
        func toImage(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale) }

        return ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: shown.width, height: shown.height)
                .offset(x: origin.x, y: origin.y)
            Canvas { ctx, _ in
                ctx.withCGContext { cg in
                    cg.translateBy(x: origin.x, y: origin.y)
                    cg.scaleBy(x: scale, y: scale)
                    let style = session.style
                    MarkupRenderer.draw(session.marks + [session.draft].compactMap { $0 }, in: cg, style: style)
                    if let i = session.selected, session.marks.indices.contains(i) {
                        let mark = session.marks[i]
                        cg.setStrokeColor(NSColor.controlAccentColor.cgColor)
                        cg.setLineWidth(2 / scale)
                        cg.setLineDash(phase: 0, lengths: [6 / scale, 4 / scale])
                        cg.stroke(mark.bounds(style: style).insetBy(dx: -6 / scale, dy: -6 / scale))
                        if session.typing == i {                     // caret after the text
                            let b = mark.bounds(style: style)
                            cg.setLineDash(phase: 0, lengths: [])
                            cg.setStrokeColor(MarkupStyle.red)
                            cg.setLineWidth(max(2 / scale, style.lineWidth / 3))
                            let x = mark.text.isEmpty ? b.minX : b.maxX + style.lineWidth / 2
                            cg.strokeLineSegments(between: [CGPoint(x: x, y: b.minY), CGPoint(x: x, y: b.maxY)])
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .frame(width: box.width, height: box.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in model.markup?.drag(from: toImage(v.startLocation), to: toImage(v.location)) }
                .onEnded { v in
                    model.markup?.endDrag(from: toImage(v.startLocation), to: toImage(v.location), tolerance: 8 / scale)
                }
        )
        .onHover { inside in inside ? NSCursor.crosshair.push() : NSCursor.pop() }
    }
}

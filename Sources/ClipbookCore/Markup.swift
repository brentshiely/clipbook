import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

public enum MarkTool: Equatable { case rectangle, arrow, text }

/// One annotation, in image pixels with the origin at the top left.
public struct Mark: Equatable {
    public var tool: MarkTool
    public var start: CGPoint
    public var end: CGPoint
    public var text: String

    public init(tool: MarkTool, start: CGPoint, end: CGPoint, text: String = "") {
        self.tool = tool
        self.start = start
        self.end = end
        self.text = text
    }

    public var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// The area the mark covers once drawn (text is measured; lines include their thickness).
    public func bounds(style: MarkupStyle) -> CGRect {
        switch tool {
        case .rectangle, .arrow: return rect.insetBy(dx: -style.lineWidth, dy: -style.lineWidth)
        case .text:
            let m = MarkupRenderer.measure(text.isEmpty ? " " : text, style: style)
            return CGRect(x: start.x, y: start.y, width: m.width, height: m.height)
        }
    }

    public func contains(_ p: CGPoint, tolerance: CGFloat, style: MarkupStyle) -> Bool {
        switch tool {
        case .rectangle, .text:
            return bounds(style: style).insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        case .arrow:
            return Self.distance(from: p, toSegment: start, end) <= tolerance + style.lineWidth
        }
    }

    mutating func offset(dx: CGFloat, dy: CGFloat) {
        start.x += dx; start.y += dy
        end.x += dx; end.y += dy
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

/// The house style: thick red lines and bold red text, sized to the image so a retina
/// screenshot and a small crop both get marks that read at a glance.
public struct MarkupStyle: Equatable {
    public let lineWidth: CGFloat
    public let fontSize: CGFloat

    public init(imageSize: CGSize) {
        let short = min(imageSize.width, imageSize.height)
        lineWidth = max(4, (short / 100).rounded())
        fontSize = max(24, (short / 20).rounded())
    }

    public static let red = CGColor(srgbRed: 0.92, green: 0.12, blue: 0.14, alpha: 1)
    static let outline = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
}

/// What the editor is doing: the marks so far, the current tool, the selection, text being typed, undo.
/// Pure state so the editing rules can be tested without a window.
public struct MarkupSession: Equatable {
    public let imageSize: CGSize
    public let style: MarkupStyle
    public private(set) var marks: [Mark] = []
    public var tool: MarkTool = .rectangle
    public private(set) var selected: Int?
    /// Index of the text mark receiving keystrokes.
    public private(set) var typing: Int?
    /// The shape being dragged out, not yet committed.
    public private(set) var draft: Mark?
    private var undoStack: [[Mark]] = []

    public init(imageSize: CGSize) {
        self.imageSize = imageSize
        self.style = MarkupStyle(imageSize: imageSize)
    }

    public var hasMarks: Bool { !marks.isEmpty }
    public var canUndo: Bool { !undoStack.isEmpty }

    public mutating func drag(from a: CGPoint, to b: CGPoint) {
        guard tool != .text else { return }
        draft = Mark(tool: tool, start: clamp(a), end: clamp(b))
    }

    /// A drag long enough to be a shape adds one; anything shorter counts as a click.
    public mutating func endDrag(from a: CGPoint, to b: CGPoint, tolerance: CGFloat) {
        draft = nil
        let moved = hypot(b.x - a.x, b.y - a.y) >= max(style.lineWidth * 2, tolerance)
        guard tool != .text, moved else { click(at: a, tolerance: tolerance); return }
        finishTyping()
        pushUndo()
        marks.append(Mark(tool: tool, start: clamp(a), end: clamp(b)))
        selected = marks.count - 1
    }

    /// With the text tool a click starts new text (or edits the text under it); otherwise it selects.
    public mutating func click(at p: CGPoint, tolerance: CGFloat) {
        finishTyping()
        let hit = marks.indices.last { marks[$0].contains(p, tolerance: tolerance, style: style) }
        guard tool == .text else { selected = hit; return }
        pushUndo()
        if let hit, marks[hit].tool == .text {
            selected = hit
        } else {
            let origin = clamp(CGPoint(x: p.x, y: p.y - style.fontSize * 0.6))
            marks.append(Mark(tool: .text, start: origin, end: origin))
            selected = marks.count - 1
        }
        typing = selected
    }

    public mutating func type(_ s: String) {
        guard let i = typing else { return }
        marks[i].text += s
    }

    public mutating func deleteBackward() {
        guard let i = typing, !marks[i].text.isEmpty else { return }
        marks[i].text.removeLast()
    }

    /// Stops typing; text left empty is removed.
    public mutating func finishTyping() {
        guard let i = typing else { return }
        typing = nil
        if marks[i].text.trimmingCharacters(in: .whitespaces).isEmpty {
            marks.remove(at: i)
            selected = nil
        }
        if undoStack.last == marks { undoStack.removeLast() }    // nothing actually changed
    }

    public mutating func deleteSelected() {
        guard let i = selected, typing == nil else { return }
        pushUndo()
        marks.remove(at: i)
        selected = nil
    }

    public mutating func nudge(dx: CGFloat, dy: CGFloat) {
        guard let i = selected, typing == nil else { return }
        pushUndo()
        marks[i].offset(dx: dx, dy: dy)
    }

    public mutating func undo() {
        typing = nil
        guard let previous = undoStack.popLast() else { return }
        marks = previous
        selected = nil
    }

    private mutating func pushUndo() { undoStack.append(marks) }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(0, p.x), imageSize.width), y: min(max(0, p.y), imageSize.height))
    }
}

public enum MarkupRenderer {
    /// Draws marks into a context whose user space is image pixels with y pointing down.
    /// Used for both the live editor and the saved PNG, so what you see is what you get.
    public static func draw(_ marks: [Mark], in ctx: CGContext, style: MarkupStyle) {
        for mark in marks { draw(mark, in: ctx, style: style) }
    }

    static func draw(_ mark: Mark, in ctx: CGContext, style: MarkupStyle) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(MarkupStyle.red)
        ctx.setFillColor(MarkupStyle.red)
        ctx.setLineWidth(style.lineWidth)
        switch mark.tool {
        case .rectangle:
            ctx.setLineJoin(.round)
            ctx.stroke(mark.rect)
        case .arrow:
            drawArrow(from: mark.start, to: mark.end, in: ctx, style: style)
        case .text:
            drawText(mark.text, at: mark.start, in: ctx, style: style)
        }
    }

    private static func drawArrow(from a: CGPoint, to b: CGPoint, in ctx: CGContext, style: MarkupStyle) {
        let len = hypot(b.x - a.x, b.y - a.y)
        guard len >= 1 else { return }
        let ux = (b.x - a.x) / len, uy = (b.y - a.y) / len
        let headLength = min(style.lineWidth * 5.5, len)
        let headHalfWidth = headLength * 0.55
        let base = CGPoint(x: b.x - ux * headLength, y: b.y - uy * headLength)
        ctx.setLineCap(.round)
        ctx.move(to: a)
        ctx.addLine(to: CGPoint(x: base.x + ux, y: base.y + uy))    // overlaps the head slightly: no seam
        ctx.strokePath()
        ctx.move(to: b)
        ctx.addLine(to: CGPoint(x: base.x - uy * headHalfWidth, y: base.y + ux * headHalfWidth))
        ctx.addLine(to: CGPoint(x: base.x + uy * headHalfWidth, y: base.y - ux * headHalfWidth))
        ctx.closePath()
        ctx.fillPath()
    }

    private static func font(_ style: MarkupStyle) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, style.fontSize, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, style.fontSize, nil)
    }

    private static func line(_ text: String, style: MarkupStyle, attributes extra: [CFString: Any]) -> CTLine {
        var attrs: [CFString: Any] = [kCTFontAttributeName: font(style)]
        attrs.merge(extra) { $1 }
        return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary))
    }

    static func measure(_ text: String, style: MarkupStyle) -> (width: CGFloat, height: CGFloat, ascent: CGFloat) {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line(text, style: style, attributes: [:]), &ascent, &descent, &leading)
        return (CGFloat(width), ascent + descent, ascent)
    }

    /// Red text with a white outline drawn underneath, so it reads on light and dark screenshots alike.
    private static func drawText(_ text: String, at origin: CGPoint, in ctx: CGContext, style: MarkupStyle) {
        guard !text.isEmpty else { return }
        let ascent = measure(text, style: style).ascent
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)         // y points down in our space
        ctx.setLineJoin(.round)
        let outline = line(text, style: style, attributes: [
            kCTStrokeWidthAttributeName: 18,                         // % of font size, stroke only
            kCTStrokeColorAttributeName: MarkupStyle.outline,
        ])
        ctx.textPosition = CGPoint(x: origin.x, y: origin.y + ascent)
        CTLineDraw(outline, ctx)
        let fill = line(text, style: style, attributes: [kCTForegroundColorAttributeName: MarkupStyle.red])
        ctx.textPosition = CGPoint(x: origin.x, y: origin.y + ascent)
        CTLineDraw(fill, ctx)
    }

    /// Bakes the marks into a copy of the image at full resolution. The original's DPI is kept,
    /// so a retina screenshot pastes at the same size as the original.
    public static func render(png: Data, marks: [Mark]) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let size = CGSize(width: image.width, height: image.height)
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        draw(marks, in: ctx, style: MarkupStyle(imageSize: size))
        guard let output = ctx.makeImage() else { return nil }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        var props: [CFString: Any] = [:]
        for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] { props[key] = original[key] }
        CGImageDestinationAddImage(dest, output, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Pixel size of an encoded image.
    public static func pixelSize(of png: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: w, height: h)
    }
}

import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import ClipbookCore

final class MarkupTests: XCTestCase {
    private let size = CGSize(width: 1200, height: 800)

    // MARK: Editing rules

    func testDragDrawsAShapeWithTheCurrentTool() {
        var s = MarkupSession(imageSize: size)
        s.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        XCTAssertEqual(s.draft?.tool, .rectangle)
        s.endDrag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200), tolerance: 8)
        XCTAssertNil(s.draft)
        XCTAssertEqual(s.marks.count, 1)
        XCTAssertEqual(s.marks[0].rect, CGRect(x: 100, y: 100, width: 200, height: 100))
        XCTAssertEqual(s.selected, 0)

        s.tool = .arrow
        s.endDrag(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 400, y: 400), tolerance: 8)
        XCTAssertEqual(s.marks.map(\.tool), [.rectangle, .arrow])
        XCTAssertEqual(s.selected, 1)
    }

    func testTinyDragIsAClickThatSelects() {
        var s = MarkupSession(imageSize: size)
        s.endDrag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200), tolerance: 8)
        s.endDrag(from: CGPoint(x: 900, y: 600), to: CGPoint(x: 902, y: 601), tolerance: 8)
        XCTAssertEqual(s.marks.count, 1, "a 2-pixel wiggle must not leave a speck")
        XCTAssertNil(s.selected, "clicking empty space clears the selection")
        s.click(at: CGPoint(x: 150, y: 150), tolerance: 8)
        XCTAssertEqual(s.selected, 0)
    }

    func testShapesStayInsideTheImage() {
        var s = MarkupSession(imageSize: size)
        s.endDrag(from: CGPoint(x: -50, y: -50), to: CGPoint(x: 5000, y: 5000), tolerance: 8)
        XCTAssertEqual(s.marks[0].rect, CGRect(origin: .zero, size: size))
    }

    func testTypingText() {
        var s = MarkupSession(imageSize: size)
        s.tool = .text
        s.click(at: CGPoint(x: 200, y: 200), tolerance: 8)
        XCTAssertEqual(s.typing, 0)
        s.type("Clikc")
        s.deleteBackward(); s.deleteBackward()
        s.type("ck here")
        s.finishTyping()
        XCTAssertNil(s.typing)
        XCTAssertEqual(s.marks.map(\.text), ["Click here"])
    }

    func testEmptyTextIsDropped() {
        var s = MarkupSession(imageSize: size)
        s.tool = .text
        s.click(at: CGPoint(x: 200, y: 200), tolerance: 8)
        s.finishTyping()
        XCTAssertTrue(s.marks.isEmpty)
        XCTAssertFalse(s.canUndo, "an abandoned text box isn't an undo step")
    }

    func testClickingExistingTextEditsIt() {
        var s = MarkupSession(imageSize: size)
        s.tool = .text
        s.click(at: CGPoint(x: 200, y: 200), tolerance: 8)
        s.type("Hi")
        s.finishTyping()
        let center = CGPoint(x: s.marks[0].bounds(style: s.style).midX, y: s.marks[0].bounds(style: s.style).midY)
        s.click(at: center, tolerance: 8)
        s.type("!")
        s.finishTyping()
        XCTAssertEqual(s.marks.map(\.text), ["Hi!"])
    }

    func testUndoDeleteAndNudge() {
        var s = MarkupSession(imageSize: size)
        s.endDrag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200), tolerance: 8)
        s.nudge(dx: 10, dy: -5)
        XCTAssertEqual(s.marks[0].rect.origin, CGPoint(x: 110, y: 95))
        s.deleteSelected()
        XCTAssertTrue(s.marks.isEmpty)
        s.undo()
        XCTAssertEqual(s.marks[0].rect.origin, CGPoint(x: 110, y: 95))
        s.undo()
        XCTAssertEqual(s.marks[0].rect.origin, CGPoint(x: 100, y: 100))
        s.undo()
        XCTAssertTrue(s.marks.isEmpty)
        XCTAssertFalse(s.canUndo)
    }

    func testArrowHitTestFollowsTheLine() {
        let style = MarkupStyle(imageSize: size)
        let arrow = Mark(tool: .arrow, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 400, y: 400))
        XCTAssertTrue(arrow.contains(CGPoint(x: 200, y: 205), tolerance: 4, style: style))
        XCTAssertFalse(arrow.contains(CGPoint(x: 300, y: 100), tolerance: 4, style: style),
                       "the empty corner of the arrow's bounding box isn't the arrow")
    }

    func testStyleScalesWithTheImage() {
        let retina = MarkupStyle(imageSize: CGSize(width: 2880, height: 1800))
        let small = MarkupStyle(imageSize: CGSize(width: 200, height: 120))
        XCTAssertEqual(retina.lineWidth, 18)
        XCTAssertEqual(small.lineWidth, 4, "never thinner than 4 px")
        XCTAssertGreaterThan(retina.fontSize, small.fontSize)
    }

    // MARK: Rendering

    func testRenderBakesMarksAtFullResolutionAndKeepsDPI() throws {
        let png = try makePNG(width: 1200, height: 800, gray: 0.5, dpi: 144)
        let marks = [
            Mark(tool: .rectangle, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 500, y: 400)),
            Mark(tool: .arrow, start: CGPoint(x: 1100, y: 700), end: CGPoint(x: 800, y: 500)),
            Mark(tool: .text, start: CGPoint(x: 600, y: 80), end: CGPoint(x: 600, y: 80), text: "Look"),
        ]
        let out = try XCTUnwrap(MarkupRenderer.render(png: png, marks: marks))
        XCTAssertEqual(MarkupRenderer.pixelSize(of: out), CGSize(width: 1200, height: 800))

        let source = try XCTUnwrap(CGImageSourceCreateWithData(out as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyDPIWidth] as? Int, 144)

        let pixels = try rgba(out)
        XCTAssertTrue(isRed(pixels.at(100, 250)), "rectangle's left edge is red")
        XCTAssertTrue(isRed(pixels.at(300, 100)), "rectangle's top edge is red, measured from the top")
        XCTAssertFalse(isRed(pixels.at(300, 250)), "inside the rectangle is untouched")
        XCTAssertTrue(isRed(pixels.at(805, 503)), "arrowhead sits at the end point")
        XCTAssertTrue(isRed(pixels.at(1000, 633)), "arrow shaft runs between the points")
        XCTAssertFalse(isRed(pixels.at(1150, 50)), "untouched corner")
        let textReds = (600..<760).flatMap { x in (80..<130).map { y in pixels.at(x, y) } }.filter(isRed).count
        XCTAssertGreaterThan(textReds, 200, "the text was drawn where it was placed")
    }

    func testRenderWithNoMarksKeepsTheImage() throws {
        let png = try makePNG(width: 40, height: 30, gray: 0.25, dpi: 72)
        let out = try XCTUnwrap(MarkupRenderer.render(png: png, marks: []))
        XCTAssertEqual(try rgba(out).at(20, 15).r, 64, accuracy: 2)
    }

    // MARK: Helpers

    private func makePNG(width: Int, height: Int, gray: CGFloat, dpi: Int) throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return data as Data
    }

    private struct Pixels {
        let bytes: [UInt8], width: Int
        func at(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double) {
            let i = (y * width + x) * 4
            return (Double(bytes[i]), Double(bytes[i + 1]), Double(bytes[i + 2]))
        }
    }

    /// Decodes to RGBA rows, top row first.
    private func rgba(_ png: Data) throws -> Pixels {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Pixels(bytes: bytes, width: image.width)
    }

    private func isRed(_ p: (r: Double, g: Double, b: Double)) -> Bool { p.r > 200 && p.g < 80 && p.b < 80 }
}

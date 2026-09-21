import XCTest
import AVFoundation
import AppKit
@testable import ClipbookCore

/// Writes a tiny real movie (solid red frames) so thumbnails are tested against a genuine file.
func makeTestMovie(width: Int = 160, height: Int = 90, seconds: Int = 2) async throws -> String {
    let path = NSTemporaryDirectory() + "clipbook-test-\(UUID().uuidString).mov"
    let writer = try AVAssetWriter(outputURL: URL(fileURLWithPath: path), fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    for frame in 0..<(seconds * 10) {
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32ARGB, nil, &buffer)
        guard let buffer else { throw NSError(domain: "test", code: 1) }
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let o = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
                base[o] = 255; base[o + 1] = 220; base[o + 2] = 20; base[o + 3] = 20   // A R G B: red
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? NSError(domain: "test", code: 2) }
    return path
}

final class VideoThumbnailTests: XCTestCase {
    func testDetectsVideoFilesOnly() async throws {
        let movie = try await makeTestMovie()
        addTeardownBlock { try? FileManager.default.removeItem(atPath: movie) }
        XCTAssertTrue(VideoThumbnail.isVideo(path: movie))

        let text = NSTemporaryDirectory() + "clipbook-test-\(UUID().uuidString).txt"
        try "hi".write(toFile: text, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: text) }
        XCTAssertFalse(VideoThumbnail.isVideo(path: text))
        XCTAssertFalse(VideoThumbnail.isVideo(path: "/nonexistent/clip.mov"))
    }

    func testThumbnailIsARealFrame() async throws {
        let movie = try await makeTestMovie(width: 160, height: 90)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: movie) }
        let jpeg = await VideoThumbnail.jpegThumbnail(forFileAt: movie)
        let data = try XCTUnwrap(jpeg)
        let image = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(image.pixelsWide, 160)
        XCTAssertEqual(image.pixelsHigh, 90)
        let center = try XCTUnwrap(image.colorAt(x: 80, y: 45))
        XCTAssertGreaterThan(center.redComponent, 0.7)      // the frame is the red video, not a blank image
        XCTAssertLessThan(center.greenComponent, 0.3)
    }

    func testUndecodableFileGivesNoThumbnail() async throws {
        let bogus = NSTemporaryDirectory() + "clipbook-test-\(UUID().uuidString).mov"
        try Data("not a movie".utf8).write(to: URL(fileURLWithPath: bogus))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: bogus) }
        let thumb = await VideoThumbnail.jpegThumbnail(forFileAt: bogus)
        XCTAssertNil(thumb)
    }

    func testWatcherCapturesCopiedVideoWithThumbnail() async throws {
        let movie = try await makeTestMovie()
        addTeardownBlock { try? FileManager.default.removeItem(atPath: movie) }

        let pb = NSPasteboard(name: NSPasteboard.Name("clipbook-test-\(UUID().uuidString)"))
        let captured = expectation(description: "video captured")
        var result: ClipPayload?
        let watcher = PasteboardWatcher(pasteboard: pb) { payload, _ in result = payload; captured.fulfill() }

        pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: movie) as NSURL])
        watcher.poll()
        await fulfillment(of: [captured], timeout: 10)

        guard case .video(let path, let thumbnail)? = result else { return XCTFail("expected .video, got \(String(describing: result))") }
        XCTAssertTrue(path.hasSuffix((movie as NSString).lastPathComponent))
        XCTAssertFalse(thumbnail.isEmpty)
    }

    func testVideoRoundTripsThroughStoreAndFooterCount() throws {
        let path = NSTemporaryDirectory() + "clipbook-test-\(UUID().uuidString).sqlite"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        let store = try ClipStore(path: path)
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00])
        try store.insert(.video(path: "/tmp/a.mov", thumbnail: jpeg))
        XCTAssertEqual(try store.fetch(limit: 1).first?.payload, .video(path: "/tmp/a.mov", thumbnail: jpeg))

        var nav = GridNavigation(count: 137)       // 8 columns -> rows 0...17, the last row holding 1 item
        XCTAssertEqual(nav.itemsBelow(total: 137), 129)
        for _ in 0..<16 { nav.move(.down) }
        XCTAssertEqual(nav.itemsBelow(total: 137), 1)
        nav.move(.down)
        XCTAssertEqual(nav.itemsBelow(total: 137), 0)   // on the last row: nothing further below
        XCTAssertEqual(GridNavigation(count: 10).itemsBelow(total: 10), 2)   // 10 items: 2 sit below row 0
    }
}

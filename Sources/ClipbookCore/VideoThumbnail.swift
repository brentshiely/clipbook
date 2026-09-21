import AVFoundation
import AppKit
import UniformTypeIdentifiers

public enum VideoBackfill {
    /// Gives thumbnails to already-saved single video files. Returns how many were converted.
    /// Safe to run on every launch: converted items no longer match, and missing or undecodable files are skipped.
    @discardableResult
    public static func run(on store: ClipStore) async -> Int {
        var converted = 0
        for candidate in (try? store.singleFileItems()) ?? [] where VideoThumbnail.isVideo(path: candidate.path) {
            guard let thumbnail = await VideoThumbnail.jpegThumbnail(forFileAt: candidate.path) else { continue }
            if (try? store.convertToVideo(id: candidate.id, path: candidate.path, thumbnail: thumbnail)) != nil { converted += 1 }
        }
        return converted
    }
}

public enum VideoThumbnail {
    /// True when `path` is an existing file whose type is a movie.
    public static func isVideo(path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path),
              let type = UTType(filenameExtension: (path as NSString).pathExtension) else { return false }
        return type.conforms(to: .movie)
    }

    /// JPEG of an early frame (about one second in, or the midpoint of a shorter clip),
    /// or nil if the file can't be decoded.
    public static func jpegThumbnail(forFileAt path: String, maxDimension: CGFloat = 640) async -> Data? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        var seconds = 1.0
        if let duration = try? await asset.load(.duration), duration.isNumeric, duration.seconds > 0 {
            seconds = min(1.0, duration.seconds / 2)
        }
        do {
            let (frame, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            return NSBitmapImageRep(cgImage: frame).representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        } catch {
            return nil
        }
    }
}

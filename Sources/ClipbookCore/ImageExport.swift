import Foundation

/// Writes a copied image out as a regular PNG file.
public enum ImageExport {
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Clipbook", isDirectory: true)
    }

    /// "Clipbook 2026-11-01 at 09.30.15.png"; a numeric suffix is added if that name is taken.
    @discardableResult
    public static func save(png: Data, to directory: URL = defaultDirectory, date: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Clipbook \(f.string(from: date))"
        var url = directory.appendingPathComponent(base + ".png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base) \(n).png")
            n += 1
        }
        try png.write(to: url, options: .atomic)
        return url
    }
}

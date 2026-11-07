import AppKit

/// Puts several history items on the clipboard at once, in the order they were copied.
public enum MultiCopy {
    /// Oldest first, so a run of screenshots pastes as step 1, 2, 3 however it was selected.
    public static func chronological(_ items: [ClipItem]) -> [ClipItem] {
        items.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// Where image files for the clipboard are written; replaced on every multi-copy.
    public static var defaultFileDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clipbook/Copied", isDirectory: true)
    }

    /// One pasteboard item per history item. All-text selections become a single block of text
    /// (most apps only paste the first text item). Images carry both the PNG and a PNG file, so
    /// image-friendly apps (Notes, Mail) and file-friendly ones (Finder, Slack uploads) both accept them.
    public static func pasteboardItems(for items: [ClipItem], fileDirectory: URL = defaultFileDirectory) -> [NSPasteboardItem] {
        let ordered = chronological(items)
        let texts = ordered.compactMap { item -> String? in
            if case .text(let s) = item.payload { return s }
            return nil
        }
        if texts.count == ordered.count {
            let item = NSPasteboardItem()
            item.setString(texts.joined(separator: "\n"), forType: .string)
            return [item]
        }

        try? FileManager.default.removeItem(at: fileDirectory)
        try? FileManager.default.createDirectory(at: fileDirectory, withIntermediateDirectories: true)
        var imageNumber = 0
        return ordered.flatMap { clip -> [NSPasteboardItem] in
            switch clip.payload {
            case .text(let s):
                let item = NSPasteboardItem()
                item.setString(s, forType: .string)
                return [item]
            case .image(let png):
                imageNumber += 1
                let item = NSPasteboardItem()
                item.setData(png, forType: .png)
                let url = fileDirectory.appendingPathComponent(String(format: "Clipbook %02d.png", imageNumber))
                if (try? png.write(to: url)) != nil {
                    item.setString(url.absoluteString, forType: .fileURL)
                }
                return [item]
            case .files(let paths):
                return paths.map(fileItem)
            case .video(let path, _):
                return [fileItem(path)]
            }
        }
    }

    private static func fileItem(_ path: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
        return item
    }
}

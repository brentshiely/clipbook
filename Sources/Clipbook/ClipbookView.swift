import SwiftUI
import ImageIO
import ClipbookCore

enum Thumbnails {
    private static let cache = NSCache<NSNumber, NSImage>()

    static func image(for id: Int64, png: Data, maxPixel: CGFloat) -> NSImage? {
        let key = NSNumber(value: id)
        if let hit = cache.object(forKey: key) { return hit }
        guard let source = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel * 2,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Picks the largest font size at which `text` fits the box without breaking words mid-word,
/// so a single short word fills the tile and long text steps down.
enum TextFit {
    static func fontSize(for text: String, in box: CGSize, maxSize: CGFloat, minSize: CGFloat) -> CGFloat {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)

        func fits(_ size: CGFloat) -> Bool {
            let font = NSFont.systemFont(ofSize: size, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            for word in words where (word as NSString).size(withAttributes: attrs).width > box.width { return false }
            let rect = (text as NSString).boundingRect(
                with: NSSize(width: box.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
            return ceil(rect.height) <= box.height
        }

        if fits(maxSize) { return maxSize }
        var low = minSize, high = maxSize
        for _ in 0..<10 {
            let mid = (low + high) / 2
            if fits(mid) { low = mid } else { high = mid }
        }
        return floor(low)
    }
}

struct TileView: View {
    let item: ClipItem
    let size: CGFloat
    let selected: Bool

    var body: some View {
        content
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 12).fill(background))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 4 : 1)
            )
    }

    private var background: Color {
        if case .image = item.payload { return .black }   // letterbox behind whole-image thumbnails
        return Color(nsColor: .controlBackgroundColor)
    }

    @ViewBuilder private var content: some View {
        switch item.payload {
        case .text(let s):
            textTile(s)
        case .image(let png):
            if let image = Thumbnails.image(for: item.id, png: png, maxPixel: size) {
                Image(nsImage: image).resizable().scaledToFit()   // the whole image, never cropped
            } else {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.white)
            }
        case .files(let paths):
            VStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: paths[0]))
                    .resizable().frame(width: size * 0.5, height: size * 0.5)
                Text((paths[0] as NSString).lastPathComponent + (paths.count > 1 ? " +\(paths.count - 1)" : ""))
                    .font(.system(size: max(11, size / 9), weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(8)
        }
    }

    @ViewBuilder private func textTile(_ raw: String) -> some View {
        let text = String(raw.prefix(240)).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            Text("(blank)").font(.system(size: 14)).foregroundStyle(.secondary)
        } else {
            let inset = size * 0.08
            let box = CGSize(width: size - 2 * inset, height: size - 2 * inset)
            let fontSize = TextFit.fontSize(for: text, in: box, maxSize: size * 0.5, minSize: 12)
            let singleWord = text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
            let big = singleWord || fontSize >= size * 0.2
            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .lineLimit(max(1, Int(box.height / (fontSize * 1.2))))
                .multilineTextAlignment(big ? .center : .leading)
                .frame(width: box.width, height: box.height, alignment: big ? .center : .topLeading)
        }
    }
}

struct ClipbookView: View {
    @ObservedObject var model: ClipbookViewModel
    let tileSize: CGFloat
    static let spacing: CGFloat = 8
    static let gridPadding: CGFloat = 4     // room for the selection outline so scrolling doesn't clip it

    private var columns: Int { GridNavigation.defaultColumns }
    private var rows: Int { GridNavigation.visibleRows }
    private var gridWidth: CGFloat { CGFloat(columns) * tileSize + CGFloat(columns - 1) * Self.spacing }
    private var gridHeight: CGFloat { CGFloat(rows) * tileSize + CGFloat(rows - 1) * Self.spacing }

    var body: some View {
        VStack(spacing: 10) {
            header
            ZStack {
                grid
                if model.items.isEmpty {
                    Text("Nothing copied yet").font(.title3).foregroundStyle(.secondary)
                }
            }
            .frame(width: gridWidth + 2 * Self.gridPadding, height: gridHeight + 2 * Self.gridPadding)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.15)))
        .overlay { if model.confirmingClear { clearDialog } }
    }

    private var header: some View {
        HStack {
            Text("Clipbook").font(.headline)
            Text("\(model.totalCount.formatted()) item\(model.totalCount == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            Spacer()
            Text("←↑↓→ move   ↩ paste   ⌘⌫ clear   esc close")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: gridWidth)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(tileSize), spacing: Self.spacing), count: columns),
                    spacing: Self.spacing
                ) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        TileView(item: item, size: tileSize, selected: index == model.nav.selected)
                    }
                }
                .padding(Self.gridPadding)
            }
            .onChange(of: model.nav.selected) { _, _ in
                if let id = model.selectedItem?.id { proxy.scrollTo(id) }
            }
        }
    }

    private var clearDialog: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.45))
            VStack(spacing: 10) {
                Text("Clear \(model.totalCount.formatted()) item\(model.totalCount == 1 ? "" : "s")?")
                    .font(.title3.bold())
                Text("This can't be undone.").foregroundStyle(.secondary)
                Text("↩ Clear everything     esc Cancel").font(.callout)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
        }
    }
}

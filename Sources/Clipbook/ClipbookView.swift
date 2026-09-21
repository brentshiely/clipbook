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

struct TileView: View {
    let item: ClipItem
    let size: CGFloat
    let selected: Bool

    var body: some View {
        content
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 3 : 1)
            )
    }

    @ViewBuilder private var content: some View {
        switch item.payload {
        case .text(let s):
            Text(String(s.prefix(160)))
                .font(.system(size: max(8, size / 9)))
                .lineLimit(7)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(6)
        case .image(let png):
            if let image = Thumbnails.image(for: item.id, png: png, maxPixel: size) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").font(.title)
            }
        case .files(let paths):
            VStack(spacing: 4) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: paths[0]))
                    .resizable().frame(width: size * 0.4, height: size * 0.4)
                Text((paths[0] as NSString).lastPathComponent + (paths.count > 1 ? " +\(paths.count - 1)" : ""))
                    .font(.system(size: max(8, size / 10)))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(4)
        }
    }
}

struct ClipbookView: View {
    @ObservedObject var model: ClipbookViewModel
    let tileSize: CGFloat
    static let spacing: CGFloat = 6
    static let columns = 10

    private var gridSide: CGFloat { CGFloat(Self.columns) * tileSize + CGFloat(Self.columns - 1) * Self.spacing }
    private var gridHeight: CGFloat { 10 * tileSize + 9 * Self.spacing }

    var body: some View {
        VStack(spacing: 10) {
            header
            ZStack {
                grid
                if model.items.isEmpty {
                    Text("Nothing copied yet").font(.title3).foregroundStyle(.secondary)
                }
            }
            .frame(width: gridSide, height: gridHeight)
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
        .frame(width: gridSide)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(tileSize), spacing: Self.spacing), count: Self.columns),
                    spacing: Self.spacing
                ) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        TileView(item: item, size: tileSize, selected: index == model.nav.selected)
                    }
                }
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

import AppKit
import AVFoundation
import ClipbookCore

@MainActor
final class ClipbookViewModel: ObservableObject {
    static let pageSize = 200

    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var nav = GridNavigation(count: 0)
    @Published private(set) var totalCount = 0
    @Published var confirmingClear = false
    @Published private(set) var player: AVPlayer?
    @Published private(set) var playbackError: String?
    @Published private(set) var notice: String?

    var onPaste: ((ClipItem) -> Void)?
    var onClose: (() -> Void)?

    private let store: ClipStore
    private var hasMore = true

    init(store: ClipStore) { self.store = store }

    var selectedItem: ClipItem? {
        items.indices.contains(nav.selected) ? items[nav.selected] : nil
    }

    /// Reload from the top with the newest tile selected.
    func reload() {
        items = fetch(offset: 0)
        hasMore = items.count == Self.pageSize
        nav = GridNavigation(count: items.count)
        totalCount = (try? store.count()) ?? items.count
        confirmingClear = false
        notice = nil
        stopPlaying()
    }

    func move(_ direction: GridMove) {
        nav.move(direction)
        if hasMore && nav.isNearEnd() { loadMore() }
    }

    /// Plays the selected video inside the panel. The saved thumbnail stays in the grid;
    /// the file itself may have moved since it was copied.
    func playSelected() {
        guard let item = selectedItem, case .video(let path, _) = item.payload else { return }
        guard FileManager.default.fileExists(atPath: path) else {
            playbackError = "\((path as NSString).lastPathComponent) is no longer at the place it was copied from."
            return
        }
        playbackError = nil
        let p = AVPlayer(url: URL(fileURLWithPath: path))
        player = p
        p.play()
    }

    func stopPlaying() {
        player?.pause()
        player = nil
        playbackError = nil
    }

    var isPlaying: Bool { player != nil || playbackError != nil }

    private func togglePlayback() {
        guard let p = player else { return }
        if p.timeControlStatus == .paused {
            if let d = p.currentItem?.duration.seconds, d.isFinite, p.currentTime().seconds >= d - 0.1 {
                p.seek(to: .zero)
            }
            p.play()
        } else {
            p.pause()
        }
    }

    private func seek(by seconds: Double) {
        guard let p = player else { return }
        let target = max(0, p.currentTime().seconds + seconds)
        p.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// ⌘S: writes the selected image to ~/Pictures/Clipbook as a PNG and shows it in Finder.
    func saveSelectedImage() {
        guard let item = selectedItem, case .image(let png) = item.payload else {
            flash("Select an image to save it as a file")
            return
        }
        do {
            let url = try ImageExport.save(png: png)
            flash("Saved \(url.lastPathComponent)")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            flash("Could not save: \(error.localizedDescription)")
        }
    }

    private func flash(_ message: String) {
        notice = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self?.notice == message { self?.notice = nil }
        }
    }

    /// Mouse: one click selects, a double click pastes.
    func click(index: Int) {
        guard !isPlaying, !confirmingClear else { return }
        nav.select(index)
        if hasMore && nav.isNearEnd() { loadMore() }
    }

    func doubleClick(index: Int) {
        guard !isPlaying, !confirmingClear else { return }
        nav.select(index)
        pasteSelected()
    }

    func pasteSelected() {
        if let item = selectedItem { onPaste?(item) }
    }

    /// ⌫ removes the selected tile for good (the row is overwritten in the database).
    func deleteSelected() {
        guard let item = selectedItem else { return }
        do { try store.delete(id: item.id) } catch { NSLog("Clipbook: delete failed: \(error)"); return }
        items.removeAll { $0.id == item.id }
        totalCount = max(0, totalCount - 1)
        nav.count = items.count
        nav.clampToCount()
    }

    func clearAll() {
        try? store.clear()
        reload()
    }

    /// Returns true when the key was handled.
    func handleKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        if confirmingClear {
            switch keyCode {
            case 36, 76: clearAll()               // return / enter
            case 53: confirmingClear = false       // esc
            default: break
            }
            return true                            // swallow everything while the dialog is up
        }
        if isPlaying {
            switch keyCode {
            case 49: togglePlayback()                  // space
            case 123: seek(by: -5)
            case 124: seek(by: 5)
            case 53: stopPlaying()                     // esc closes the player, not the panel
            case 36, 76: stopPlaying(); pasteSelected()
            default: break
            }
            return true
        }
        switch keyCode {
        case 1 where modifiers.contains(.command): saveSelectedImage()      // ⌘S
        case 49: playSelected()                        // space
        case 123: move(.left)
        case 124: move(.right)
        case 125: move(.down)
        case 126: move(.up)
        case 36, 76: pasteSelected()
        case 53: onClose?()
        case 51 where modifiers.contains(.command): if totalCount > 0 { confirmingClear = true }
        case 51, 117: deleteSelected()                  // delete / forward delete
        default: return false
        }
        return true
    }

    private func loadMore() {
        let next = fetch(offset: items.count)
        items += next
        hasMore = next.count == Self.pageSize
        nav.count = items.count
    }

    private func fetch(offset: Int) -> [ClipItem] {
        (try? store.fetch(limit: Self.pageSize, offset: offset)) ?? []
    }
}

import AppKit

/// Polls NSPasteboard's change count (macOS has no clipboard-change notification)
/// and reports each new, non-concealed item.
public final class PasteboardWatcher {
    public static let concealedTypes: Set<String> = SensitiveSource.flaggedTypes

    private let pasteboard: NSPasteboard
    private let onCapture: (ClipPayload, Date) -> Void
    private var lastChangeCount: Int
    private var timer: Timer?
    private let frontmostBundleID: () -> String?
    private var previousFrontmostBundleID: String?

    public init(
        pasteboard: NSPasteboard = .general,
        frontmostBundleID: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
        onCapture: @escaping (ClipPayload, Date) -> Void
    ) {
        self.pasteboard = pasteboard
        self.frontmostBundleID = frontmostBundleID
        self.onCapture = onCapture
        self.lastChangeCount = pasteboard.changeCount
    }

    public func start(interval: TimeInterval = 0.4) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call after Clipbook itself writes to the pasteboard so it isn't re-captured.
    public func ignoreCurrentContents() {
        lastChangeCount = pasteboard.changeCount
    }

    public func poll() {
        let front = frontmostBundleID()
        defer { previousFrontmostBundleID = front }
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // Never keep a copy made in a password manager. The previous poll's app counts too, so
        // switching away right after copying doesn't let it through.
        if SensitiveSource.isPasswordManager(bundleID: front)
            || SensitiveSource.isPasswordManager(bundleID: previousFrontmostBundleID) { return }
        guard let payload = Self.payload(from: pasteboard) else { return }
        let date = Date()   // ordering follows when it was copied, not when its thumbnail finished

        // A single copied video file gets a frame thumbnail, generated off the main thread.
        if case .files(let paths) = payload, paths.count == 1, VideoThumbnail.isVideo(path: paths[0]) {
            let path = paths[0]
            let onCapture = self.onCapture
            Task { @MainActor in
                if let thumb = await VideoThumbnail.jpegThumbnail(forFileAt: path) {
                    onCapture(.video(path: path, thumbnail: thumb), date)
                } else {
                    onCapture(payload, date)
                }
            }
        } else {
            onCapture(payload, date)
        }
    }

    /// Files > image > text, skipping concealed items.
    public static func payload(from pasteboard: NSPasteboard) -> ClipPayload? {
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        if !types.isDisjoint(with: concealedTypes) { return nil }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return .files(urls.map(\.path))
        }
        if let png = pasteboard.data(forType: .png) {
            return .image(png)
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return .image(png)
        }
        if let s = pasteboard.string(forType: .string), !s.isEmpty {
            return .text(s)
        }
        return nil
    }
}

import Foundation

public struct TileAction: Equatable {
    public let keys: String
    public let title: String
}

/// The one place that lists what you can do with a tile. The hover tooltip is built from it,
/// so a new command only needs adding here (and in ClipbookViewModel.handleKey).
public enum TileActions {
    public static func actions(for payload: ClipPayload) -> [TileAction] {
        var list: [TileAction] = []
        switch payload {
        case .image:
            list.append(TileAction(keys: "E", title: "Mark up with a red box, arrow or text"))
            list.append(TileAction(keys: "⌘S", title: "Save as a PNG file in Pictures/Clipbook"))
        case .video:
            list.append(TileAction(keys: "space", title: "Play here (space pauses, ←/→ seek 5 s)"))
            list.append(TileAction(keys: "⌘S", title: "Show the video file in Finder"))
        case .text, .files:
            break
        }
        list.append(TileAction(keys: "↩ or double-click", title: "Paste"))
        list.append(TileAction(keys: "⌫", title: "Delete"))
        return list
    }

    public static func tooltip(for payload: ClipPayload) -> String {
        actions(for: payload).map { "\($0.keys)   \($0.title)" }.joined(separator: "\n")
    }
}

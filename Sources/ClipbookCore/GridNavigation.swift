import Foundation

public enum GridMove { case left, right, up, down }

/// Selection logic for the tile grid. Index 0 is the newest item (top left);
/// tiles read left to right, then down one row.
public struct GridNavigation: Equatable {
    /// v1.1: 8 columns x 3 visible rows so each tile is large enough to read.
    public static let defaultColumns = 8
    public static let visibleRows = 3

    public let columns: Int
    public private(set) var selected: Int = 0
    public var count: Int

    public init(columns: Int = GridNavigation.defaultColumns, count: Int) {
        self.columns = columns
        self.count = count
    }

    public var row: Int { selected / columns }
    public var column: Int { selected % columns }

    public mutating func move(_ direction: GridMove) {
        guard count > 0 else { return }
        switch direction {
        case .left:
            selected = max(selected - 1, 0)                 // wraps to end of previous row
        case .right:
            selected = min(selected + 1, count - 1)         // wraps to start of next row
        case .up:
            if selected >= columns { selected -= columns }
        case .down:
            let below = selected + columns
            if below < count {
                selected = below
            } else if row < (count - 1) / columns {
                selected = count - 1                        // short last row: land on its final tile
            }
        }
    }

    public mutating func reset() { selected = 0 }

    /// True when the selection is within `rows` rows of the end of what's loaded.
    public func isNearEnd(rows: Int = 3) -> Bool {
        row >= max(0, (count - 1) / columns - rows)
    }
}

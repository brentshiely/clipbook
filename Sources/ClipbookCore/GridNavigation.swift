import Foundation

public enum GridMove { case left, right, up, down }

/// Selection logic for the tile grid. Index 0 is the newest item (top left);
/// tiles read left to right, then down one row.
public struct GridNavigation: Equatable {
    /// v1.1: 8 columns x 3 visible rows so each tile is large enough to read.
    public static let defaultColumns = 8
    public static let visibleRows = 3

    public let columns: Int
    /// The cursor: the tile arrows move from and single-tile actions apply to.
    public private(set) var selected: Int = 0
    public var count: Int
    /// Where a ⇧-extended range started; nil when no range is being extended.
    public private(set) var anchor: Int?
    /// Tiles picked with ⌘-click, kept alongside any range.
    public private(set) var picked: Set<Int> = []

    public init(columns: Int = GridNavigation.defaultColumns, count: Int) {
        self.columns = columns
        self.count = count
    }

    public var row: Int { selected / columns }
    public var column: Int { selected % columns }

    /// A plain arrow moves the cursor and drops any multi-selection.
    public mutating func move(_ direction: GridMove) {
        clearMultiSelection()
        step(direction)
    }

    /// ⇧+arrow: grows (or shrinks) a contiguous range, in reading order, from where it started.
    public mutating func extend(_ direction: GridMove) {
        if anchor == nil { anchor = selected }
        step(direction)
    }

    /// ⇧-click: the range runs from where it started to this tile.
    public mutating func extend(to index: Int) {
        guard index >= 0 && index < count else { return }
        if anchor == nil { anchor = selected }
        selected = index
    }

    /// ⌘-click: adds or removes one tile, keeping everything else selected.
    public mutating func toggle(_ index: Int) {
        guard index >= 0 && index < count else { return }
        var set = selection
        if set.contains(index) { set.remove(index) } else { set.insert(index) }
        picked = set
        anchor = nil
        selected = index
    }

    /// Every selected tile: the range plus ⌘-picked tiles, or just the cursor.
    public var selection: Set<Int> {
        var set = picked
        if let anchor { set.formUnion(min(anchor, selected)...max(anchor, selected)) }
        if set.isEmpty { set.insert(selected) }
        return set.filter { $0 < count }
    }

    public var isMultiSelecting: Bool { selection.count > 1 }

    public mutating func clearMultiSelection() {
        anchor = nil
        picked = []
    }

    private mutating func step(_ direction: GridMove) {
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

    /// Mouse selection: jump straight to a tile; out-of-range indexes are ignored.
    public mutating func select(_ index: Int) {
        guard index >= 0 && index < count else { return }
        clearMultiSelection()
        selected = index
    }

    public mutating func reset() {
        clearMultiSelection()
        selected = 0
    }

    /// After items are removed: keep the selection on a real tile (the last one if it was the end).
    public mutating func clampToCount() {
        clearMultiSelection()
        selected = count > 0 ? min(selected, count - 1) : 0
    }

    /// Items in the rows below the selected row, out of `total` items overall (for the footer indicator).
    public func itemsBelow(total: Int) -> Int { max(0, total - (row + 1) * columns) }

    /// True when the selection is within `rows` rows of the end of what's loaded.
    public func isNearEnd(rows: Int = 3) -> Bool {
        row >= max(0, (count - 1) / columns - rows)
    }
}

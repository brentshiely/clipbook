import AppKit
import ClipbookCore

@MainActor
final class ClipbookViewModel: ObservableObject {
    static let pageSize = 200

    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var nav = GridNavigation(count: 0)
    @Published private(set) var totalCount = 0
    @Published var confirmingClear = false

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
    }

    func move(_ direction: GridMove) {
        nav.move(direction)
        if hasMore && nav.isNearEnd() { loadMore() }
    }

    func pasteSelected() {
        if let item = selectedItem { onPaste?(item) }
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
        switch keyCode {
        case 123: move(.left)
        case 124: move(.right)
        case 125: move(.down)
        case 126: move(.up)
        case 36, 76: pasteSelected()
        case 53: onClose?()
        case 51 where modifiers.contains(.command): if totalCount > 0 { confirmingClear = true }
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

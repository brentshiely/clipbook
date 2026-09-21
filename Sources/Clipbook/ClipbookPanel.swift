import AppKit
import SwiftUI
import ClipbookCore

/// Non-activating so the app you were typing in stays frontmost; that makes paste-back a plain ⌘V.
final class ClipbookPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) != true { super.keyDown(with: event) }
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

@MainActor
final class ClipbookPanelController {
    private let model: ClipbookViewModel
    private let panel: ClipbookPanel

    static func tileSize(for screen: NSScreen?) -> CGFloat {
        guard let frame = screen?.visibleFrame else { return 64 }
        let cols = CGFloat(GridNavigation.defaultColumns), rows = CGFloat(GridNavigation.visibleRows)
        let pad = 32 + 2 * ClipbookView.gridPadding
        let byWidth = (frame.width * 0.92 - pad - (cols - 1) * ClipbookView.spacing) / cols
        let byHeight = (frame.height * 0.92 - pad - 40 - (rows - 1) * ClipbookView.spacing) / rows
        return max(80, floor(min(220, byWidth, byHeight)))
    }

    init(model: ClipbookViewModel) {
        self.model = model
        let tile = Self.tileSize(for: NSScreen.main)
        panel = ClipbookPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: ClipbookView(model: model, tileSize: tile))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)

        panel.keyHandler = { [weak self] event in
            self?.model.handleKey(keyCode: event.keyCode, modifiers: event.modifierFlags) ?? false
        }
        panel.onResignKey = { [weak self] in self?.hide() }
        model.onClose = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { isVisible ? hide() : show() }

    func show(confirmClear: Bool = false) {
        model.reload()
        if confirmClear && model.totalCount > 0 { model.confirmingClear = true }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }
}

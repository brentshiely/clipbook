import AppKit
import ServiceManagement
import Carbon.HIToolbox
import ClipbookCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store: ClipStore
    private let model: ClipbookViewModel
    private var watcher: PasteboardWatcher!
    private var panelController: ClipbookPanelController!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!

    init(store: ClipStore) {
        self.store = store
        self.model = ClipbookViewModel(store: store)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        watcher = PasteboardWatcher { [store] payload, date in
            do { try store.insert(payload, at: date) } catch { NSLog("Clipbook: insert failed: \(error)") }
        }
        watcher.start()

        panelController = ClipbookPanelController(model: model)
        model.onPaste = { [weak self] item in self?.paste(item) }

        hotKey = HotKey(keyCode: kVK_ANSI_V, modifiers: cmdKey | shiftKey) { [weak self] in
            Task { @MainActor in self?.panelController.toggle() }
        }
        if hotKey == nil { NSLog("Clipbook: ⇧⌘V is taken by another app; use the menu-bar item.") }

        buildStatusItem()
        enableLaunchAtLoginOnFirstRun()
    }

    // MARK: - Launch at login

    private let loginItem = SMAppService.mainApp

    /// On by default; the menu checkbox turns it off. Only runs once so an "off" choice sticks.
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "didApplyLaunchAtLoginDefault"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        do { try loginItem.register() } catch { NSLog("Clipbook: launch at login failed: \(error)") }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if loginItem.status == .enabled { try loginItem.unregister() } else { try loginItem.register() }
        } catch {
            NSLog("Clipbook: launch at login toggle failed: \(error)")
        }
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Clipbook")
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Clipbook", action: #selector(openClipbook), keyEquivalent: "v")
        open.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(open)
        menu.addItem(NSMenuItem(title: "Clear Clipbook…", action: #selector(clearClipbook), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit Clipbook", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func openClipbook() { panelController.show() }
    @objc private func clearClipbook() { panelController.show(confirmClear: true) }

    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first { $0.action == #selector(toggleLaunchAtLogin(_:)) }?.state =
            loginItem.status == .enabled ? .on : .off
    }

    // MARK: - Paste

    private func paste(_ item: ClipItem) {
        panelController.hide()
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.payload {
        case .text(let s): pb.setString(s, forType: .string)
        case .image(let png): pb.setData(png, forType: .png)
        case .files(let paths): pb.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
        case .video(let path, _): pb.writeObjects([URL(fileURLWithPath: path) as NSURL])
        }
        watcher.ignoreCurrentContents()   // pasting shouldn't reorder history

        // Synthesizing ⌘V needs the Accessibility permission; without it the item is still on the clipboard.
        guard AXIsProcessTrusted() else {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let src = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}

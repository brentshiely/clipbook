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

    /// Menu-bar-only apps never appear in ⌘Tab. After the first time you open Clipbook we switch to a
    /// regular app (⌘Tab + Dock) for the rest of this run; a fresh launch/login starts menu-bar-only again.
    private var isCommandTabbable = false
    /// The app you were in before Clipbook, so Esc / paste can hand focus straight back to it.
    private var lastFrontmost: NSRunningApplication?

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

        model.onClose = { [weak self] in self?.dismiss() }

        hotKey = HotKey(keyCode: kVK_ANSI_V, modifiers: cmdKey | shiftKey) { [weak self] in
            Task { @MainActor in self?.togglePanel() }
        }
        if hotKey == nil { NSLog("Clipbook: ⇧⌘V is taken by another app; use the menu-bar item.") }

        buildStatusItem()
        buildMainMenu()
        trackFrontmostApp()
        enableLaunchAtLoginOnFirstRun()

        // Older copied videos (saved before thumbnails existed) get theirs now.
        Task { @MainActor [store, model] in
            if await VideoBackfill.run(on: store) > 0 { model.reload() }
        }
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

    @objc private func openClipbook() { openPanel() }
    @objc private func clearClipbook() { openPanel(confirmClear: true) }

    // MARK: - Opening, closing, ⌘Tab

    private func openPanel(confirmClear: Bool = false) {
        if !isCommandTabbable {
            isCommandTabbable = true
            NSApp.setActivationPolicy(.regular)     // now in ⌘Tab and the Dock
        }
        panelController.show(confirmClear: confirmClear)
    }

    private func togglePanel() {
        panelController.isVisible ? dismiss() : openPanel()
    }

    /// Esc, ↩, or the hotkey again: close the grid and, if Clipbook itself is frontmost
    /// (you ⌘Tabbed to it), hand focus back to the app you came from.
    private func dismiss() {
        panelController.hide()
        returnFocusToPreviousApp()
    }

    @discardableResult
    private func returnFocusToPreviousApp() -> Bool {
        guard NSApp.isActive, let previous = lastFrontmost, !previous.isTerminated else { return false }
        previous.activate()
        return true
    }

    private func trackFrontmostApp() {
        let me = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != me { lastFrontmost = front }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != me else { return }
            Task { @MainActor in self?.lastFrontmost = app }
        }
    }

    /// ⌘Tab (or a Dock click) activates Clipbook: show the grid.
    func applicationDidBecomeActive(_ notification: Notification) {
        if isCommandTabbable, !panelController.isVisible { panelController.show() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !panelController.isVisible { openPanel() }
        return true
    }

    /// A regular app needs a menu bar; this gives ⌘Q, ⌘H and a way to open the grid.
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu(title: "Clipbook")
        let open = NSMenuItem(title: "Open Clipbook", action: #selector(openClipbook), keyEquivalent: "")
        open.target = self
        appMenu.addItem(open)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Clipbook", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Quit Clipbook", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first { $0.action == #selector(toggleLaunchAtLogin(_:)) }?.state =
            loginItem.status == .enabled ? .on : .off
    }

    // MARK: - Paste

    private func paste(_ item: ClipItem) {
        panelController.hide()
        let switchedApps = returnFocusToPreviousApp()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + (switchedApps ? 0.25 : 0.08)) {
            let src = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}

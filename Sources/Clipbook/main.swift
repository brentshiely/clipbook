import AppKit
import ClipbookCore

// Card 1: headless capture. Later cards add the menu-bar item, hotkey and grid.
let store = try ClipStore(path: ClipStore.defaultPath())
let watcher = PasteboardWatcher { payload in
    do { try store.insert(payload) } catch { NSLog("Clipbook: insert failed: \(error)") }
}
watcher.start()
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()

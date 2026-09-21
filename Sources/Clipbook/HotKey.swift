import Carbon.HIToolbox

/// Global hotkey via Carbon's RegisterEventHotKey (needs no special permission).
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    init?(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        Self.installHandlerIfNeeded()
        let id = Self.nextID
        Self.nextID += 1
        Self.handlers[id] = handler
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C4950) /* 'CLIP' */, id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { return nil }
    }

    deinit { if let ref { UnregisterEventHotKey(ref) } }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            HotKey.handlers[hotKeyID.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
}

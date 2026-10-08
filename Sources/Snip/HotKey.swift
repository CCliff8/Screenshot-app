import Carbon.HIToolbox

/// System-wide hotkeys via Carbon; needs no accessibility permission.
final class HotKey {
    static let shared = HotKey()
    var actions: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            HotKey.shared.actions[id.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Returns false if the combo is unavailable (e.g. taken by the system or another app).
    @discardableResult
    func register(_ s: Shortcut, id: UInt32) -> Bool {
        unregister(id: id)
        var ref: EventHotKeyRef?
        let hid = EventHotKeyID(signature: OSType(0x534E4950), id: id)
        let status = RegisterEventHotKey(UInt32(s.keyCode), UInt32(s.modifiers), hid, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[id] = ref }
        return status == noErr
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    }

    func unregisterAll() {
        for id in Array(refs.keys) { unregister(id: id) }
    }
}

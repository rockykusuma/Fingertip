import AppKit
import Carbon.HIToolbox

/// Thin wrapper over Carbon's RegisterEventHotKey. Still the only public
/// API for system-wide hotkeys that works while the app is inactive.
final class HotKeys {
    struct Key {
        let code: UInt32
        let modifiers: UInt32

        static let controlOption = UInt32(controlKey | optionKey)
        static func ctrlOpt(_ code: UInt32) -> Key { Key(code: code, modifiers: controlOption) }

        // Virtual key codes (ANSI layout).
        static let h: UInt32 = 0x04
        static let x: UInt32 = 0x07
        static let l: UInt32 = 0x25
        static let s: UInt32 = 0x01
        static let a: UInt32 = 0x00
        static let n: UInt32 = 0x2D
        static let escape: UInt32 = 0x35
    }

    private static let signature: OSType = 0x4654_4950  // "FTIP"
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, refcon in
            guard let refcon, let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID
            )
            guard status == noErr else { return status }
            let me = Unmanaged<HotKeys>.fromOpaque(refcon).takeUnretainedValue()
            me.handlers[hkID.id]?()
            return noErr
        }, 1, &spec, refcon, &eventHandler)
    }

    /// Registers a hotkey and returns a token for `unregister`.
    @discardableResult
    func register(_ key: Key, _ action: @escaping () -> Void) -> UInt32 {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(key.code, key.modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[id] = ref
            handlers[id] = action
        } else {
            NSLog("Fingertip: hotkey register failed (%d) for code 0x%02X", status, key.code)
        }
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers[id] = nil
    }

    deinit {
        refs.values.forEach { UnregisterEventHotKey($0) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

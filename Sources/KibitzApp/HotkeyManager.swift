import AppKit
import Carbon.HIToolbox

/// A global shortcut via Carbon's hotkey API.
///
/// Deliberately not a CGEvent tap: this needs no Accessibility permission of its
/// own, so the app can react to the hotkey and explain the permission situation
/// even before Accessibility has been granted.
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onFire: (() -> Void)?

    /// Cmd+Shift+E by default.
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_E),
                  modifiers: UInt32 = UInt32(cmdKey | shiftKey),
                  onFire: @escaping () -> Void) {
        unregister()
        self.onFire = onFire

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context else { return noErr }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue()
            manager.onFire?()
            return noErr
        }, 1, &eventType, context, &eventHandler)

        let identifier = EventHotKeyID(signature: OSType(0x4B42_5A21), id: 1) // 'KBZ!'
        RegisterEventHotKey(keyCode, modifiers, identifier,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    deinit { unregister() }
}

import AppKit
import Carbon

final class GlobalHotkey {
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    private(set) var available = false

    init(key: UInt32, signature: OSType) {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue()
            owner.action?()
            return noErr
        }, 1, &event, pointer, &handler)
        guard status == noErr else { return }
        available = RegisterEventHotKey(key, UInt32(controlKey | optionKey),
            EventHotKeyID(signature: signature, id: 1), GetApplicationEventTarget(), 0, &hotkey) == noErr
    }
    deinit {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

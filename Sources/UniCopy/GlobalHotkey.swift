import AppKit
import Carbon
import UniCopyCore

final class GlobalHotkey {
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    private(set) var available = false
    private let identifier: EventHotKeyID

    init(shortcut: KeyboardShortcut, id: UInt32 = 1) {
        identifier = EventHotKeyID(signature: 0x554E4943, id: id)
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue()
            var received = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &received) == noErr,
                  received.signature == owner.identifier.signature, received.id == owner.identifier.id else { return OSStatus(eventNotHandledErr) }
            owner.action?()
            return noErr
        }, 1, &event, pointer, &handler)
        guard status == noErr else { return }
        guard shortcut.isValid else { return }
        var modifiers: UInt32 = 0
        for (mask, carbon) in [(KeyboardShortcut.control, controlKey), (KeyboardShortcut.option, optionKey),
                               (KeyboardShortcut.shift, shiftKey), (KeyboardShortcut.command, cmdKey)] {
            if shortcut.modifiers & mask != 0 { modifiers |= UInt32(carbon) }
        }
        available = RegisterEventHotKey(shortcut.keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &hotkey) == noErr
    }
    deinit {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

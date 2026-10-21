import Carbon
import Foundation

/// Registers one system-wide hotkey and calls `onPress` on the main thread.
final class HotkeyManager {
    enum HotkeyError: Error { case installHandler(OSStatus), register(OSStatus) }

    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x504D_484B // "PMHK"

    func register(keyCode: UInt32 = UInt32(kVK_ANSI_G),
                  modifiers: UInt32 = UInt32(cmdKey | shiftKey)) throws {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onPress?()
                return noErr
            },
            1, &spec, selfPtr, &handlerRef
        )
        guard installStatus == noErr else { throw HotkeyError.installHandler(installStatus) }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registerStatus == noErr else { throw HotkeyError.register(registerStatus) }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

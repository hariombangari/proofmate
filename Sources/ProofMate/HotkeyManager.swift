import Carbon
import Foundation
import ProofMateCore

/// Registers one system-wide hotkey and calls `onPress` on the main thread.
final class HotkeyManager {
    enum HotkeyError: Error { case installHandler(OSStatus), register(OSStatus) }

    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x504D_484B // "PMHK"

    /// Replaces any previously registered shortcut.
    func register(_ hotkey: Hotkey) throws {
        try installHandlerIfNeeded()
        unregister()
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            hotkey.keyCode, hotkey.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard status == noErr else {
            hotKeyRef = nil
            throw HotkeyError.register(status)
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() throws {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onPress?()
                return noErr
            },
            1, &spec, selfPtr, &handlerRef
        )
        guard status == noErr else { throw HotkeyError.installHandler(status) }
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

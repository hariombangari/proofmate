import Foundation

/// A global shortcut stored as a Carbon key code plus Carbon modifier flags.
public struct Hotkey: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    /// The key's label when recorded, e.g. "G". Display only.
    public var key: String

    // Carbon modifier bits (HIToolbox Events.h), duplicated so Core stays UI-free.
    static let cmd: UInt32 = 1 << 8
    static let shift: UInt32 = 1 << 9
    static let option: UInt32 = 1 << 11
    static let control: UInt32 = 1 << 12

    // NSEvent.ModifierFlags raw bits.
    private static let cocoaShift: UInt = 1 << 17
    private static let cocoaControl: UInt = 1 << 18
    private static let cocoaOption: UInt = 1 << 19
    private static let cocoaCommand: UInt = 1 << 20

    /// Keys whose typed character is blank or unreadable.
    private static let specialKeyLabels: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    public init(keyCode: UInt32, carbonModifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.key = key
    }

    /// Control+Option+G. Cmd+Shift+G clashed with other apps during v1 testing.
    public static let defaultCheck = Hotkey(keyCode: 5, carbonModifiers: control | option, key: "G")

    /// Builds a hotkey from an AppKit key event. Returns nil unless Command, Control, or
    /// Option is held: Shift-only or bare keys would hijack normal typing.
    ///
    /// Pass `NSEvent.charactersIgnoringModifiers` as `characters`. `NSEvent.characters`
    /// applies the modifiers, so ⌥G gives "©" and ⌃G gives a control character.
    public static func fromCocoa(keyCode: UInt16, cocoaFlags: UInt, characters: String) -> Hotkey? {
        var modifiers: UInt32 = 0
        if cocoaFlags & cocoaCommand != 0 { modifiers |= cmd }
        if cocoaFlags & cocoaShift != 0 { modifiers |= shift }
        if cocoaFlags & cocoaOption != 0 { modifiers |= option }
        if cocoaFlags & cocoaControl != 0 { modifiers |= control }
        guard modifiers & (cmd | control | option) != 0 else { return nil }

        let label = specialKeyLabels[keyCode]
            ?? characters.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !label.isEmpty else { return nil }
        return Hotkey(keyCode: UInt32(keyCode), carbonModifiers: modifiers, key: label)
    }

    /// True when Command, Control, or Option is set and the key label is not empty.
    /// A hand-edited settings file could hold a bare or Shift-only key, which would hijack typing.
    public var isValid: Bool {
        carbonModifiers & (Self.cmd | Self.control | Self.option) != 0 && !key.isEmpty
    }

    /// Modifiers in the standard macOS order (⌃⌥⇧⌘), then the key.
    public var displayString: String {
        var text = ""
        if carbonModifiers & Self.control != 0 { text += "⌃" }
        if carbonModifiers & Self.option != 0 { text += "⌥" }
        if carbonModifiers & Self.shift != 0 { text += "⇧" }
        if carbonModifiers & Self.cmd != 0 { text += "⌘" }
        return text + key
    }
}

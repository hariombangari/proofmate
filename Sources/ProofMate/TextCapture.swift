import AppKit
import ApplicationServices
import Carbon

enum CaptureError: Error {
    case accessibilityDenied
    case noSelection
}

enum TextCapture {
    // MARK: - Permission

    /// Returns true if this app may use Accessibility. With `prompt: true` macOS shows its own
    /// "grant access" dialog the first time.
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Read

    @MainActor
    static func selectedText() async throws -> String {
        if let text = accessibilitySelectedText(), !text.isEmpty {
            return text
        }
        return try await clipboardSelectedText()
    }

    /// Asks the frontmost app, not the system-wide element: on macOS 26 the system-wide
    /// focused-element query can fail or return an element from another app.
    private static func accessibilitySelectedText() -> String? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedRef = focused else { return nil }
        let element = focusedRef as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    /// Sends Cmd+C to the frontmost app, reads the result, and restores the old clipboard.
    @MainActor
    private static func clipboardSelectedText() async throws -> String {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount
        defer { snapshot.restore(to: pasteboard) }

        sendKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        // Wait up to 300 ms for the target app to write the clipboard.
        for _ in 0..<15 where pasteboard.changeCount == before {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard pasteboard.changeCount != before,
              let text = pasteboard.string(forType: .string),
              !text.isEmpty else {
            throw CaptureError.noSelection
        }
        return text
    }

    // MARK: - Write

    /// Pastes `text` over the current selection in the frontmost app, then restores the clipboard.
    @MainActor
    static func replaceSelection(with text: String) async throws {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        sendKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

        // Give the target app time to consume the paste before restoring.
        try await Task.sleep(nanoseconds: 200_000_000)
        snapshot.restore(to: pasteboard)
    }

    // MARK: - Keystrokes

    private static func sendKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

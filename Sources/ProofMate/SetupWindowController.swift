import AppKit
import SwiftUI

@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    let model: SetupModel
    private var window: NSWindow?

    init(model: SetupModel) {
        self.model = model
    }

    /// True only when the user is looking at the setup window, so a window left open
    /// behind other apps does not swallow real checks.
    var isFrontmost: Bool { NSApp.isActive && (window?.isKeyWindow ?? false) }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        Self.forceActivate()
        window.makeKeyAndOrderFront(nil)
        model.startMonitoring()
    }

    // Cooperative NSApp.activate() is ignored when an accessory app is launched from the background,
    // so the first-run window would open without focus. The deprecated call still takes focus.
    @available(macOS, deprecated: 100)
    private static func forceActivate() {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// While the window is open the hotkey proves itself instead of running a check.
    func hotkeyPressed() {
        model.hotkeyVerified = true
    }

    func windowWillClose(_ notification: Notification) {
        model.stopMonitoring()
    }

    private func makeWindow() -> NSWindow {
        let view = SetupView(model: model) { [weak self] in
            self?.model.complete()
            self?.window?.close()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "ProofMate Setup"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}

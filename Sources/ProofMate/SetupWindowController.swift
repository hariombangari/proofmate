import AppKit
import SwiftUI

@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    let model: SetupModel
    private var window: NSWindow?

    init(model: SetupModel) {
        self.model = model
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        model.startMonitoring()
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

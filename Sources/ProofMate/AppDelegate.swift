import AppKit
import os
import ProofMateCore

let log = Logger(subsystem: "com.hari.proofmate", category: "app")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "text.badge.checkmark",
            accessibilityDescription: "ProofMate"
        )
        statusItem.menu = makeMenu()
        log.info("ProofMate \(ProofMateVersion.current, privacy: .public) launched")
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "ProofMate \(ProofMateVersion.current)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
}

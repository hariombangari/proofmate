import AppKit
import os
import ProofMateCore

let log = Logger(subsystem: "com.hari.proofmate", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkey = HotkeyManager()
    private var coordinator: Coordinator!
    private let store = SettingsStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = Coordinator(store: store, openSetup: { [weak self] in self?.openSettings() })

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "text.badge.checkmark",
            accessibilityDescription: "ProofMate"
        )
        statusItem.menu = makeMenu()

        hotkey.onPress = { [weak self] in self?.coordinator.checkSelection() }
        do {
            try hotkey.register(store.settings.hotkey)
        } catch {
            log.error("hotkey registration failed: \(String(describing: error))")
        }

        log.info("ProofMate \(ProofMateVersion.current, privacy: .public) launched with model \(self.store.settings.model, privacy: .public)")
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "ProofMate \(ProofMateVersion.current) · \(store.settings.model)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let check = NSMenuItem(title: "Check Selection  \(store.settings.hotkey.displayString)", action: #selector(checkSelection), keyEquivalent: "")
        check.target = self
        menu.addItem(check)

        let open = NSMenuItem(title: "Open Settings File", action: #selector(openSettings), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func checkSelection() {
        coordinator.checkSelection()
    }

    @objc private func openSettings() {
        NSWorkspace.shared.open(Settings.defaultFileURL)
    }
}

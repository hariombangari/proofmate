import AppKit
import os
import ProofMateCore

let log = Logger(subsystem: "com.hari.proofmate", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkey = HotkeyManager()
    private var coordinator: Coordinator!
    private var settings = Settings.defaults

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = loadSettings()
        coordinator = Coordinator(engine: OllamaEngine(settings: settings), settings: settings)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "text.badge.checkmark",
            accessibilityDescription: "ProofMate"
        )
        statusItem.menu = makeMenu()

        hotkey.onPress = { [weak self] in self?.coordinator.checkSelection() }
        do {
            try hotkey.register()
        } catch {
            log.error("hotkey registration failed: \(String(describing: error))")
        }

        log.info("ProofMate \(ProofMateVersion.current, privacy: .public) launched with model \(self.settings.model, privacy: .public)")
    }

    /// Loads settings, writing the defaults file on first run so the user has something to edit.
    private func loadSettings() -> Settings {
        let url = Settings.defaultFileURL
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try Settings.defaults.save(to: url)
            }
            return try Settings.load(from: url)
        } catch {
            log.error("settings load failed, using defaults: \(String(describing: error))")
            return .defaults
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "ProofMate \(ProofMateVersion.current) · \(settings.model)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let check = NSMenuItem(title: "Check Selection  ⌃⌥G", action: #selector(checkSelection), keyEquivalent: "")
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

import AppKit
import os
import ProofMateCore

let log = Logger(subsystem: "com.hari.proofmate", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let hotkey = HotkeyManager()
    private let store = SettingsStore()
    private var coordinator: Coordinator!
    private var setup: SetupWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let setupModel = SetupModel(
            store: store,
            registerHotkey: { [weak self] in self?.registerHotkey($0) },
            unregisterHotkey: { [weak self] in self?.hotkey.unregister() }
        )
        setup = SetupWindowController(model: setupModel)
        coordinator = Coordinator(store: store, openSetup: { [weak self] in self?.setup.show() })

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "text.badge.checkmark",
            accessibilityDescription: "ProofMate"
        )
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        menuNeedsUpdate(menu)
        NSApp.mainMenu = makeMainMenu()

        hotkey.onPress = { [weak self] in self?.hotkeyPressed() }
        _ = registerHotkey(store.settings.hotkey)

        log.info("ProofMate \(ProofMateVersion.current, privacy: .public) launched with model \(self.store.settings.model, privacy: .public)")

        if !store.settings.hasCompletedOnboarding {
            setup.show()
        }
    }

    /// Returns a user-facing error message, or nil on success.
    private func registerHotkey(_ shortcut: Hotkey) -> String? {
        do {
            try hotkey.register(shortcut)
            return nil
        } catch {
            log.error("hotkey registration failed for \(shortcut.displayString, privacy: .public): \(String(describing: error))")
            return "Could not register \(shortcut.displayString). Choose another shortcut."
        }
    }

    private func hotkeyPressed() {
        if setup.isFrontmost {
            setup.hotkeyPressed()
        } else {
            coordinator.checkSelection()
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = store.settings
        menu.addItem(withTitle: "ProofMate \(ProofMateVersion.current) · \(settings.model)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(item("Check Selection  \(settings.hotkey.displayString)", #selector(checkSelection)))
        menu.addItem(item("Settings…", #selector(openSetup), key: ","))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ProofMate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// An accessory app has no main menu by default, so edit shortcuts (⌘C, ⌘V, ⌘W…) would not
    /// reach the setup window's text field. The menu bar stays hidden for LSUIElement apps.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "ProofMate")
        main.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func checkSelection() {
        coordinator.checkSelection()
    }

    @objc private func openSetup() {
        setup.show()
    }
}

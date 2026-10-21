import AppKit
import Carbon
import Combine
import ProofMateCore
import ServiceManagement

@MainActor
final class SetupModel: ObservableObject {
    enum OllamaState: Equatable {
        case checking
        case notInstalled
        case notRunning
        case running(version: String)
        case error(String)
    }

    enum TryState: Equatable {
        case idle
        case running
        case result(String)
        case failed(String)
    }

    static let sampleText = "I has a apple and she dont like it."
    static let ollamaAppPaths = ["/Applications/Ollama.app", NSHomeDirectory() + "/Applications/Ollama.app"]
    static let ollamaCLIPaths = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]

    @Published private(set) var accessibilityGranted = false
    @Published private(set) var ollama: OllamaState = .checking
    @Published private(set) var models: [ModelSuggestion] = []
    @Published var hotkeyVerified = false
    @Published private(set) var isRecordingHotkey = false
    @Published private(set) var hotkeyError: String?
    @Published private(set) var tryState: TryState = .idle
    @Published var endpointText: String
    @Published private(set) var endpointError: String?
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var launchAtLoginError: String?

    let store: SettingsStore
    /// Registers the given hotkey as the global shortcut, replacing any registered one.
    /// Returns a user-facing error message, or nil on success. The model calls it with a
    /// newly recorded hotkey before saving it, and with `settings.hotkey` to restore the
    /// saved one, so a failed registration never leaves the app without a shortcut.
    private let registerHotkey: (Hotkey) -> String?
    private let unregisterHotkey: () -> Void
    private var pollTimer: Timer?
    private var keyMonitor: Any?
    private var storeChanges: AnyCancellable?
    /// Bumped by each `refreshOllama` call, so an older, slower refresh cannot overwrite a newer one.
    private var refreshGeneration = 0

    init(store: SettingsStore,
         registerHotkey: @escaping (Hotkey) -> String?,
         unregisterHotkey: @escaping () -> Void) {
        self.store = store
        self.registerHotkey = registerHotkey
        self.unregisterHotkey = unregisterHotkey
        endpointText = store.settings.endpoint.absoluteString
        // Views observe this model only, so forward the store's changes.
        storeChanges = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var settings: Settings { store.settings }
    var pullCommand: String { "ollama pull \(ModelAdvisor.suggestedPull)" }
    var selectedSuggestion: ModelSuggestion? { models.first { $0.model.name == settings.model } }

    var isReady: Bool {
        guard accessibilityGranted, case .running = ollama else { return false }
        return selectedSuggestion != nil
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        pollAccessibility()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if launchAtLogin { launchAtLoginError = nil }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollAccessibility() }
        }
        Task { await refreshOllama() }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        if isRecordingHotkey { stopRecording() }
    }

    func complete() {
        store.update { $0.hasCompletedOnboarding = true }
    }

    // MARK: - Accessibility

    private func pollAccessibility() {
        let granted = TextCapture.ensureAccessibility(prompt: false)
        if granted != accessibilityGranted { accessibilityGranted = granted }
    }

    func requestAccessibility() {
        _ = TextCapture.ensureAccessibility(prompt: true)
        TextCapture.openAccessibilitySettings()
    }

    // MARK: - Ollama and models

    func refreshOllama() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        // Keep the model picker visible while re-checking a running server.
        if case .running = ollama {} else { ollama = .checking }
        let engine = OllamaEngine(settings: settings)
        do {
            let version = try await engine.serverVersion()
            let installed = try await engine.installedModels()
            guard generation == refreshGeneration else { return }
            ollama = .running(version: version)
            models = ModelAdvisor.assess(installed)
        } catch EngineError.notRunning {
            guard generation == refreshGeneration else { return }
            ollama = Self.isOllamaInstalled() ? .notRunning : .notInstalled
            models = []
        } catch {
            guard generation == refreshGeneration else { return }
            ollama = .error(message(for: error))
            models = []
        }
    }

    private func message(for error: Error) -> String {
        guard let engineError = error as? EngineError else { return error.localizedDescription }
        return engineError.userMessage(endpoint: settings.endpoint, timeoutSeconds: settings.timeoutSeconds)
    }

    static func isOllamaInstalled() -> Bool {
        (ollamaAppPaths + ollamaCLIPaths).contains { FileManager.default.fileExists(atPath: $0) }
    }

    func openOllamaDownload() {
        NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
    }

    func startOllama() {
        if let path = Self.ollamaAppPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await refreshOllama()
        }
    }

    func commitEndpoint() {
        guard let url = Settings.parseEndpoint(endpointText) else {
            endpointError = "Enter a full address, such as http://localhost:11434"
            return
        }
        endpointError = nil
        endpointText = url.absoluteString
        store.update { $0.endpoint = url }
        Task { await refreshOllama() }
    }

    func selectModel(_ name: String) {
        store.update { $0.model = name }
        tryState = .idle
    }

    func copyPullCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pullCommand, forType: .string)
    }

    // MARK: - Hotkey recording

    func startRecording() {
        guard !isRecordingHotkey else { return }
        unregisterHotkey()
        hotkeyError = nil
        isRecordingHotkey = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handleRecording(event) }
            return nil
        }
    }

    /// Cancels recording (Cancel button, Escape, or the window closing) and restores the saved hotkey.
    func stopRecording() {
        endRecording()
        hotkeyError = registerHotkey(settings.hotkey)
    }

    private func endRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        isRecordingHotkey = false
    }

    private func handleRecording(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { // Escape cancels and keeps the old shortcut
            stopRecording()
            return
        }
        guard let candidate = Hotkey.fromCocoa(
            keyCode: event.keyCode,
            cocoaFlags: event.modifierFlags.rawValue,
            characters: event.charactersIgnoringModifiers ?? ""
        ) else {
            NSSound.beep()
            hotkeyError = "Hold at least one of ⌃, ⌥ or ⌘ with the key."
            return
        }
        endRecording()
        // Register before saving, so a rejected shortcut never reaches disk.
        if let error = registerHotkey(candidate) {
            let old = settings.hotkey.displayString
            if registerHotkey(settings.hotkey) == nil {
                hotkeyError = "\(error) Kept \(old)."
            } else {
                hotkeyError = "\(error) Also could not restore \(old): choose another shortcut."
            }
            return
        }
        store.update { $0.hotkey = candidate }
        hotkeyError = nil
        hotkeyVerified = false
    }

    // MARK: - General

    func setTimeout(_ seconds: Double) {
        store.update { $0.timeoutSeconds = seconds }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            log.error("launch at login change failed: \(String(describing: error))")
            if SMAppService.mainApp.status == .requiresApproval {
                launchAtLoginError = "Approve ProofMate in System Settings → General → Login Items."
                SMAppService.openSystemSettingsLoginItems()
            } else {
                launchAtLoginError = "Could not change Launch at Login: \(error.localizedDescription)"
            }
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Try it

    func tryIt() async {
        tryState = .running
        let model = settings.model
        do {
            let raw = try await OllamaEngine(settings: settings).correct(Self.sampleText)
            guard settings.model == model else { return } // selectModel already reset tryState
            switch OutputCleaner.clean(raw, original: Self.sampleText) {
            case .success(let fixed):
                tryState = .result(fixed)
            case .failure:
                tryState = .failed("The model returned an unusable answer. Try another model.")
            }
        } catch {
            guard settings.model == model else { return }
            tryState = .failed(message(for: error))
        }
    }
}

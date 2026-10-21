import AppKit
import ProofMateCore

@MainActor
final class Coordinator {
    private let store: SettingsStore
    private let openSetup: () -> Void
    private let popover = PopoverController()
    private var lastOriginal: String?
    private var lastCorrected: String?

    /// Built per check so edits in the setup window apply immediately.
    private var engine: CorrectionEngine { OllamaEngine(settings: store.settings) }
    private var settings: Settings { store.settings }

    init(store: SettingsStore, openSetup: @escaping () -> Void) {
        self.store = store
        self.openSetup = openSetup
        popover.onReturn = { [weak self] in self?.apply() }
        popover.onCopy = { [weak self] in self?.copy() }
    }

    // MARK: - Entry points

    func checkSelection() {
        Task { await runCheck() }
    }

    private func runCheck() async {
        guard TextCapture.ensureAccessibility(prompt: true) else {
            popover.show(.error(
                message: "ProofMate needs Accessibility access to read the selected text.",
                action: ErrorAction(title: "Open Setup") { [weak self] in
                    self?.popover.hide()
                    self?.openSetup()
                }
            ))
            return
        }

        let text: String
        do {
            text = try await TextCapture.selectedText()
        } catch {
            log.info("no selection: \(String(describing: error))")
            popover.show(.error(message: "Select some text first.", action: nil), autoCloseAfter: 2)
            return
        }

        lastOriginal = text
        await correct(text)
    }

    private func correct(_ text: String) async {
        popover.show(.checking)
        do {
            let raw = try await engine.correct(text)
            handle(raw: raw, original: text)
        } catch let error as EngineError {
            log.error("engine error: \(String(describing: error))")
            popover.show(errorState(for: error, retrying: text))
        } catch {
            log.error("unexpected error: \(String(describing: error))")
            popover.show(.error(message: "Unexpected error: \(error.localizedDescription)", action: nil))
        }
    }

    private func handle(raw: String, original: String) {
        switch OutputCleaner.clean(raw, original: original) {
        case .success(let corrected) where corrected == original:
            popover.show(.unchanged, autoCloseAfter: 2)
        case .success(let corrected):
            lastCorrected = corrected
            popover.show(.result(
                original: original,
                corrected: corrected,
                segments: WordDiff.diff(original: original, corrected: corrected)
            ))
        case .failure(let reason):
            // Model output echoes the user's text, so keep it out of the persisted log.
            log.error("cleaner rejected output (\(String(describing: reason))): \(raw, privacy: .private)")
            popover.show(.error(
                message: "The model returned an unusable answer. Try again.",
                action: ErrorAction(title: "Retry") { [weak self] in
                    Task { await self?.correct(original) }
                }
            ))
        }
    }

    // MARK: - Actions

    private func apply() {
        guard let corrected = lastCorrected else { return }
        popover.hide()
        Task {
            do {
                try await TextCapture.replaceSelection(with: corrected)
            } catch {
                log.error("apply failed: \(String(describing: error))")
            }
        }
    }

    private func copy() {
        guard let corrected = lastCorrected else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(corrected, forType: .string)
        popover.hide()
    }

    // MARK: - Error mapping

    private func errorState(for error: EngineError, retrying text: String) -> PopoverState {
        let retry = ErrorAction(title: "Retry") { [weak self] in
            Task { await self?.correct(text) }
        }
        switch error {
        case .notRunning:
            return .error(
                message: "Ollama is not running at \(settings.endpoint.absoluteString).",
                action: ErrorAction(title: "Start Ollama") { [weak self] in
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Ollama.app"))
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await self?.correct(text)
                    }
                }
            )
        case .modelMissing(let model):
            return .error(
                message: "Model \"\(model)\" is not installed. Pick an installed model or run:  ollama pull \(model)",
                action: ErrorAction(title: "Open Setup") { [weak self] in
                    self?.popover.hide()
                    self?.openSetup()
                }
            )
        case .timeout:
            return .error(message: "The model took longer than \(Int(settings.timeoutSeconds))s.", action: retry)
        case .http(let code):
            return .error(message: "Ollama returned HTTP \(code).", action: retry)
        case .badResponse(let detail):
            return .error(message: "Bad response from Ollama: \(detail)", action: retry)
        }
    }
}

import SwiftUI
import ProofMateCore

struct AccessibilitySection: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        Section("1 · Accessibility") {
            if model.accessibilityGranted {
                StatusLabel(ok: true, text: "Access granted")
            } else {
                StatusLabel(ok: false, text: "ProofMate needs Accessibility access to read and replace selected text.")
                Button("Grant Access…") { model.requestAccessibility() }
                Text("Turn on ProofMate in the list. If it is already on but this still shows missing (common after an update), select it, remove it with −, and add it again with +.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct OllamaSection: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        Section("2 · Ollama") {
            switch model.ollama {
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking…")
                }
            case .running(let version):
                StatusLabel(ok: true, text: "Ollama \(version) is running")
            case .notRunning:
                StatusLabel(ok: false, text: "Ollama is installed but not running. Start the app, or run `ollama serve` in Terminal.")
                Button("Start Ollama") { model.startOllama() }
            case .notInstalled:
                StatusLabel(ok: false, text: "Ollama is not installed. It runs the language model on your Mac.")
                Button("Download Ollama…") { model.openOllamaDownload() }
            case .error(let message):
                StatusLabel(ok: false, text: message)
            }
            HStack {
                TextField("Server address", text: $model.endpointText)
                    .onSubmit { model.commitEndpoint() }
                Button("Check Again") { model.commitEndpoint() }
            }
            if let error = model.endpointError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

struct ModelSection: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        Section("3 · Model") {
            if case .running = model.ollama {
                if model.models.isEmpty {
                    StatusLabel(ok: false, text: "No models installed yet.")
                    pullHint
                } else {
                    picker
                    if let note = model.selectedSuggestion?.note {
                        Text(note).font(.caption).foregroundStyle(.orange)
                    }
                    if !model.models.contains(where: { $0.fit == .recommended }) {
                        pullHint
                    }
                }
            } else {
                Text("Available once Ollama is running.").foregroundStyle(.secondary)
            }
        }
    }

    private var picker: some View {
        Picker("Model", selection: Binding(
            get: { model.settings.model },
            set: { model.selectModel($0) }
        )) {
            if model.selectedSuggestion == nil {
                Text("\(model.settings.model) (not installed)").tag(model.settings.model)
            }
            ForEach(model.models, id: \.model.name) { suggestion in
                Text(label(for: suggestion)).tag(suggestion.model.name)
            }
        }
    }

    private var pullHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("To install a model, run this in Terminal, then click Refresh:")
                .font(.callout)
            HStack {
                Text(model.pullCommand)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Copy") { model.copyPullCommand() }
                Button("Refresh") { Task { await model.refreshOllama() } }
            }
        }
    }

    private func label(for suggestion: ModelSuggestion) -> String {
        let size = ByteCountFormatter.string(fromByteCount: suggestion.model.size, countStyle: .file)
        switch suggestion.fit {
        case .recommended: return "\(suggestion.model.name) · \(size) · recommended"
        case .usable: return "\(suggestion.model.name) · \(size)"
        case .notForProse: return "\(suggestion.model.name) · \(size) · not for prose"
        }
    }
}

struct ShortcutSection: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        Section("4 · Shortcut") {
            HStack {
                Text("Check selection")
                Spacer()
                Button(model.isRecordingHotkey ? "Press keys… (esc cancels)" : model.settings.hotkey.displayString) {
                    if model.isRecordingHotkey { model.stopRecording() } else { model.startRecording() }
                }
            }
            if let error = model.hotkeyError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if model.hotkeyVerified {
                StatusLabel(ok: true, text: "Shortcut received. It works.")
            } else {
                Text("Press \(model.settings.hotkey.displayString) now to test it. If nothing happens, another app owns that shortcut: click the button and choose a different one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TryItSection: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        Section("5 · Try it") {
            Text(SetupModel.sampleText).foregroundStyle(.secondary)
            switch model.tryState {
            case .idle:
                EmptyView()
            case .running:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking…")
                }
            case .result(let text):
                StatusLabel(ok: true, text: text)
            case .failed(let message):
                StatusLabel(ok: false, text: message)
            }
            Button("Run Sample") { Task { await model.tryIt() } }
                .disabled(!model.isReady || model.tryState == .running)
        }
    }
}

struct GeneralSection: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        Section("General") {
            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            if let error = model.launchAtLoginError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Stepper(value: Binding(
                get: { model.settings.timeoutSeconds },
                set: { model.setTimeout($0) }
            ), in: 5...120, step: 5) {
                Text("Timeout: \(Int(model.settings.timeoutSeconds)) s")
            }
        }
    }
}

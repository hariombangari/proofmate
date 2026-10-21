import SwiftUI

struct SetupView: View {
    @ObservedObject var model: SetupModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                AccessibilitySection(model: model)
                OllamaSection(model: model)
                ModelSection(model: model)
                ShortcutSection(model: model)
                TryItSection(model: model)
                GeneralSection(model: model)
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !model.isReady {
                    Text("Finish steps 1–3 to start using ProofMate.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.isReady)
            }
            .padding(12)
        }
        .frame(width: 540, height: 700)
    }
}

struct StatusLabel: View {
    let ok: Bool
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
        }
    }
}

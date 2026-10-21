import SwiftUI
import ProofMateCore

final class PopoverModel: ObservableObject {
    @Published var state: PopoverState = .checking
}

struct PopoverView: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
            footer
        }
        .padding(14)
        .frame(width: 420)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
        case .result(_, _, let segments):
            diffText(segments)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .unchanged:
            Label("No changes needed", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .error(let message, let action):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action.title, action: action.run)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if case .result = model.state {
            HStack {
                Text("↩ Apply").foregroundStyle(.secondary)
                Text("⌘C Copy").foregroundStyle(.secondary)
                Spacer()
                Text("esc Dismiss").foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private func diffText(_ segments: [DiffSegment]) -> Text {
        segments.enumerated().reduce(Text("")) { acc, pair in
            let (index, segment) = pair
            let space = index == 0 ? Text("") : Text(" ")
            switch segment {
            case .equal(let s):
                return acc + space + Text(s)
            case .deleted(let s):
                return acc + space + Text(s).strikethrough().foregroundColor(.red)
            case .inserted(let s):
                return acc + space + Text(s).bold().foregroundColor(.green)
            }
        }
    }
}

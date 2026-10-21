import Foundation

public enum ModelFit: Int, Comparable, Sendable {
    case recommended = 0
    case usable
    case notForProse

    public static func < (lhs: ModelFit, rhs: ModelFit) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct ModelSuggestion: Equatable, Sendable {
    public let model: OllamaModel
    public let fit: ModelFit

    public var note: String? {
        guard fit == .notForProse else { return nil }
        return "This model is built for code, embeddings, or images. Proofreading quality will be poor."
    }
}

public enum ModelAdvisor {
    /// What the setup window tells people to pull when nothing suitable is installed.
    public static let suggestedPull = "qwen3:8b"

    static let proseFamilies = ["qwen3", "gemma3", "gemma2", "llama3", "mistral", "phi4"]
    static let nonProseMarkers = ["coder", "code", "embed", "llava", "vision", "minilm", "bge"]

    public static func fit(for name: String) -> ModelFit {
        let base = (name.split(separator: "/").last.map(String.init) ?? name).lowercased()
        if nonProseMarkers.contains(where: { base.contains($0) }) { return .notForProse }
        if proseFamilies.contains(where: { base.hasPrefix($0) }) { return .recommended }
        return .usable
    }

    /// Recommended first, then usable, then not-for-prose. Server order is kept within each group.
    public static func assess(_ models: [OllamaModel]) -> [ModelSuggestion] {
        models
            .map { ModelSuggestion(model: $0, fit: fit(for: $0.name)) }
            .enumerated()
            .sorted { ($0.element.fit, $0.offset) < ($1.element.fit, $1.offset) }
            .map(\.element)
    }
}

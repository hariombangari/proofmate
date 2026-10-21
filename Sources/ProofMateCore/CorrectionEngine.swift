import Foundation

public enum EngineError: Error, Equatable {
    /// Nothing is listening on the endpoint.
    case notRunning
    /// The server answered 404, which Ollama uses for an unpulled model.
    case modelMissing(String)
    case timeout
    case http(Int)
    case badResponse(String)
}

public protocol CorrectionEngine {
    /// Returns the raw model output. Callers pass it through `OutputCleaner`.
    func correct(_ text: String) async throws -> String
}

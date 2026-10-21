import Foundation

extension EngineError {
    /// A sentence to show the user. Shared by the popover and the setup window.
    public func userMessage(endpoint: URL, timeoutSeconds: Double) -> String {
        switch self {
        case .notRunning:
            return "Ollama is not running at \(endpoint.absoluteString)."
        case .modelMissing(let model):
            return "Model \"\(model)\" is not installed. Pick an installed model or run:  ollama pull \(model)"
        case .timeout:
            return "The model took longer than \(Int(timeoutSeconds))s."
        case .http(let code):
            return "Ollama returned HTTP \(code)."
        case .badResponse(let detail):
            return "Bad response from Ollama: \(detail)"
        }
    }
}

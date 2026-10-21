import Foundation

public struct OllamaModel: Equatable, Decodable, Sendable {
    public let name: String
    public let size: Int64

    public init(name: String, size: Int64) {
        self.name = name
        self.size = size
    }
}

public final class OllamaEngine: CorrectionEngine {
    /// Status probes fail fast because the setup window calls them while the user waits.
    static let probeTimeout: TimeInterval = 3

    private let settings: Settings
    private let session: URLSession

    public init(settings: Settings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    public func correct(_ text: String) async throws -> String {
        let request = try makeChatRequest(text: text)
        let (data, response) = try await send(request)
        try checkStatus(response, notFound: .modelMissing(settings.model))
        return try decode(ChatResponse.self, from: data).message.content
    }

    /// GET /api/version. Throws `.notRunning` when nothing listens on the endpoint.
    public func serverVersion() async throws -> String {
        try await get("api/version", as: VersionResponse.self).version
    }

    /// GET /api/tags: the models already pulled, in the server's order.
    public func installedModels() async throws -> [OllamaModel] {
        try await get("api/tags", as: TagsResponse.self).models
    }

    // MARK: - Requests

    private struct ChatMessage: Encodable {
        let role: String
        let content: String
    }

    private struct ChatOptions: Encodable {
        let temperature: Double
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        let think: Bool
        let options: ChatOptions
    }

    private func makeChatRequest(text: String) throws -> URLRequest {
        var request = URLRequest(url: settings.endpoint.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = settings.timeoutSeconds
        let body = ChatRequest(
            model: settings.model,
            messages: [
                ChatMessage(role: "system", content: Prompt.system),
                ChatMessage(role: "user", content: text),
            ],
            stream: false,
            think: false,
            options: ChatOptions(temperature: 0)
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: settings.endpoint.appendingPathComponent(path))
        request.timeoutInterval = Self.probeTimeout
        let (data, response) = try await send(request)
        try checkStatus(response, notFound: .http(404))
        return try decode(type, from: data)
    }

    // MARK: - Transport

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                throw EngineError.notRunning
            case .timedOut:
                throw EngineError.timeout
            default:
                throw EngineError.badResponse(error.localizedDescription)
            }
        }
    }

    // MARK: - Responses

    private struct ChatResponse: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }

    private struct VersionResponse: Decodable { let version: String }
    private struct TagsResponse: Decodable { let models: [OllamaModel] }

    private func checkStatus(_ response: URLResponse, notFound: EngineError) throws {
        guard let http = response as? HTTPURLResponse else {
            throw EngineError.badResponse("non-HTTP response")
        }
        if http.statusCode == 404 { throw notFound }
        guard (200..<300).contains(http.statusCode) else { throw EngineError.http(http.statusCode) }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw EngineError.badResponse("could not decode: \(error)")
        }
    }
}

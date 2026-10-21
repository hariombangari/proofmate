import Foundation

public final class OllamaEngine: CorrectionEngine {
    private let settings: Settings
    private let session: URLSession

    public init(settings: Settings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    public func correct(_ text: String) async throws -> String {
        let request = try makeRequest(text: text)
        let (data, response) = try await send(request)
        return try parse(data: data, response: response)
    }

    // MARK: - Request

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

    private func makeRequest(text: String) throws -> URLRequest {
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

    // MARK: - Response

    private struct ChatResponse: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }

    private func parse(data: Data, response: URLResponse) throws -> String {
        guard let http = response as? HTTPURLResponse else {
            throw EngineError.badResponse("non-HTTP response")
        }
        if http.statusCode == 404 { throw EngineError.modelMissing(settings.model) }
        guard (200..<300).contains(http.statusCode) else { throw EngineError.http(http.statusCode) }
        do {
            return try JSONDecoder().decode(ChatResponse.self, from: data).message.content
        } catch {
            throw EngineError.badResponse("could not decode: \(error)")
        }
    }
}

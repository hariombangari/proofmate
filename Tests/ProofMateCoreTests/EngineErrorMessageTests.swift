import XCTest
@testable import ProofMateCore

final class EngineErrorMessageTests: XCTestCase {
    private let endpoint = URL(string: "http://localhost:11434")!

    private func message(_ error: EngineError) -> String {
        error.userMessage(endpoint: endpoint, timeoutSeconds: 20)
    }

    func testNotRunning() {
        XCTAssertEqual(message(.notRunning), "Ollama is not running at http://localhost:11434.")
    }

    func testModelMissing() {
        XCTAssertEqual(
            message(.modelMissing("qwen3:8b")),
            "Model \"qwen3:8b\" is not installed. Pick an installed model or run:  ollama pull qwen3:8b"
        )
    }

    func testTimeout() {
        XCTAssertEqual(message(.timeout), "The model took longer than 20s.")
    }

    func testHTTP() {
        XCTAssertEqual(message(.http(500)), "Ollama returned HTTP 500.")
    }

    func testBadResponse() {
        XCTAssertEqual(message(.badResponse("no message")), "Bad response from Ollama: no message")
    }
}

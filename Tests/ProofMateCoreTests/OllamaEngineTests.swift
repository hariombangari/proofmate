import XCTest
@testable import ProofMateCore

final class OllamaEngineTests: XCTestCase {
    private let settings = Settings(
        model: "test-model",
        endpoint: URL(string: "http://localhost:11434")!,
        timeoutSeconds: 5
    )

    private func engine() -> OllamaEngine {
        OllamaEngine(settings: settings, session: StubURLProtocol.session())
    }

    private func ok(_ content: String) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            let body = #"{"model":"test-model","message":{"role":"assistant","content":"\#(content)"},"done":true}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
    }

    func testSendsExpectedRequest() async throws {
        var captured: URLRequest?
        var capturedBody = Data()
        StubURLProtocol.handler = { request in
            captured = request
            capturedBody = StubURLProtocol.body(of: request)
            return try self.ok("fixed")(request)
        }

        _ = try await engine().correct("I has a apple.")

        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/chat")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 5)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: capturedBody) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertEqual(json["think"] as? Bool, false)
        let options = try XCTUnwrap(json["options"] as? [String: Any])
        XCTAssertEqual(options["temperature"] as? Double, 0)
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[0]["content"], Prompt.system)
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "I has a apple.")
    }

    func testReturnsAssistantContent() async throws {
        StubURLProtocol.handler = ok("I have an apple.")
        let result = try await engine().correct("I has a apple.")
        XCTAssertEqual(result, "I have an apple.")
    }

    func testConnectionRefusedMapsToNotRunning() async {
        StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        await assertThrows(.notRunning)
    }

    func testTimeoutMapsToTimeout() async {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        await assertThrows(.timeout)
    }

    func testNotFoundMapsToModelMissing() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"error":"model 'test-model' not found"}"#.utf8))
        }
        await assertThrows(.modelMissing("test-model"))
    }

    func testServerErrorMapsToHTTP() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        await assertThrows(.http(500))
    }

    func testMalformedJSONMapsToBadResponse() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("not json".utf8))
        }
        do {
            _ = try await engine().correct("x")
            XCTFail("expected throw")
        } catch let error as EngineError {
            guard case .badResponse = error else { return XCTFail("got \(error)") }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    private func assertThrows(_ expected: EngineError, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await engine().correct("x")
            XCTFail("expected throw", file: file, line: line)
        } catch let error as EngineError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }
}

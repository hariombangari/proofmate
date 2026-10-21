import XCTest
@testable import ProofMateCore

final class OllamaDiscoveryTests: XCTestCase {
    private let settings = Settings(
        model: "m", endpoint: URL(string: "http://localhost:11434")!, timeoutSeconds: 20)

    private func engine() -> OllamaEngine {
        OllamaEngine(settings: settings, session: StubURLProtocol.session())
    }

    private func respond(_ status: Int, _ body: String) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
    }

    func testServerVersion() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return try self.respond(200, #"{"version":"0.35.1"}"#)(request)
        }
        let version = try await engine().serverVersion()
        XCTAssertEqual(version, "0.35.1")
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/version")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, OllamaEngine.probeTimeout)
    }

    func testInstalledModelsDecodesNameAndSize() async throws {
        var captured: URLRequest?
        let body = #"""
        {"models":[
          {"name":"qwen3:8b","model":"qwen3:8b","size":5225388164,"digest":"x","details":{"family":"qwen3"}},
          {"name":"gemma3:12b","size":8149190253}
        ]}
        """#
        StubURLProtocol.handler = { request in
            captured = request
            return try self.respond(200, body)(request)
        }
        let models = try await engine().installedModels()
        XCTAssertEqual(models, [
            OllamaModel(name: "qwen3:8b", size: 5_225_388_164),
            OllamaModel(name: "gemma3:12b", size: 8_149_190_253),
        ])
        XCTAssertEqual(captured?.url?.absoluteString, "http://localhost:11434/api/tags")
    }

    func testInstalledModelsEmpty() async throws {
        StubURLProtocol.handler = respond(200, #"{"models":[]}"#)
        let models = try await engine().installedModels()
        XCTAssertEqual(models, [])
    }

    func testVersionWhenNotRunning() async {
        StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        do {
            _ = try await engine().serverVersion()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? EngineError, .notRunning)
        }
    }

    func testTagsServerError() async {
        StubURLProtocol.handler = respond(500, "")
        do {
            _ = try await engine().installedModels()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? EngineError, .http(500))
        }
    }

    func testTagsNotFoundIsHTTPNotModelMissing() async {
        StubURLProtocol.handler = respond(404, "")
        do {
            _ = try await engine().installedModels()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? EngineError, .http(404))
        }
    }
}

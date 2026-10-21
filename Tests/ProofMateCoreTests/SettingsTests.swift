import XCTest
@testable import ProofMateCore

final class SettingsTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("proofmate-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDir)
    }

    func testMissingFileReturnsDefaults() throws {
        let url = tempDir.appendingPathComponent("settings.json")
        let settings = try Settings.load(from: url)
        XCTAssertEqual(settings, Settings.defaults)
    }

    func testPartialJSONFallsBackPerKey() throws {
        let url = tempDir.appendingPathComponent("settings.json")
        try #"{"model": "qwen3:14b"}"#.write(to: url, atomically: true, encoding: .utf8)
        let settings = try Settings.load(from: url)
        XCTAssertEqual(settings.model, "qwen3:14b")
        XCTAssertEqual(settings.endpoint, Settings.defaults.endpoint)
        XCTAssertEqual(settings.timeoutSeconds, Settings.defaults.timeoutSeconds)
    }

    func testFullJSONRoundTrips() throws {
        let url = tempDir.appendingPathComponent("settings.json")
        let original = Settings(
            model: "gemma3:12b",
            endpoint: URL(string: "http://127.0.0.1:9999")!,
            timeoutSeconds: 5
        )
        try original.save(to: url)
        XCTAssertEqual(try Settings.load(from: url), original)
    }

    func testInvalidJSONThrows() throws {
        let url = tempDir.appendingPathComponent("settings.json")
        try "{not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Settings.load(from: url))
    }

    func testDefaults() {
        XCTAssertEqual(Settings.defaults.model, "qwen3:8b")
        XCTAssertEqual(Settings.defaults.endpoint.absoluteString, "http://localhost:11434")
        XCTAssertEqual(Settings.defaults.timeoutSeconds, 20)
    }
}

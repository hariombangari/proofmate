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

    func testNewKeysDefaultWhenMissing() throws {
        let url = tempDir.appendingPathComponent("settings.json")
        try #"{"model": "qwen3:14b"}"#.write(to: url, atomically: true, encoding: .utf8)
        let settings = try Settings.load(from: url)
        XCTAssertEqual(settings.hotkey, .defaultCheck)
        XCTAssertFalse(settings.hasCompletedOnboarding)
    }

    func testHotkeyAndOnboardingRoundTrip() throws {
        let url = tempDir.appendingPathComponent("settings.json")
        let original = Settings(
            model: "qwen3:8b",
            endpoint: URL(string: "http://localhost:11434")!,
            timeoutSeconds: 20,
            hotkey: Hotkey(keyCode: 40, carbonModifiers: 256 | 2048, key: "K"),
            hasCompletedOnboarding: true
        )
        try original.save(to: url)
        XCTAssertEqual(try Settings.load(from: url), original)
    }

    func testInvalidHotkeyFallsBackToDefault() throws {
        let url = tempDir.appendingPathComponent("settings.json")
        try #"{"hotkey": {"keyCode": 5, "carbonModifiers": 0, "key": "G"}}"#
            .write(to: url, atomically: true, encoding: .utf8)
        let settings = try Settings.load(from: url)
        XCTAssertEqual(settings.hotkey, .defaultCheck)
    }

    func testParseEndpointAcceptsHTTPAndHTTPS() {
        XCTAssertEqual(Settings.parseEndpoint("http://localhost:11434")?.absoluteString, "http://localhost:11434")
        XCTAssertEqual(Settings.parseEndpoint("  https://ollama.example.com  ")?.absoluteString, "https://ollama.example.com")
    }

    func testParseEndpointRejectsIncompleteAddresses() {
        XCTAssertNil(Settings.parseEndpoint("localhost:11434"))
        XCTAssertNil(Settings.parseEndpoint("ftp://localhost"))
        XCTAssertNil(Settings.parseEndpoint("http://"))
        XCTAssertNil(Settings.parseEndpoint(""))
    }
}

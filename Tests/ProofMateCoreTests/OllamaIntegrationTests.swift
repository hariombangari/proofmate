import XCTest
@testable import ProofMateCore

final class OllamaIntegrationTests: XCTestCase {
    func testRealOllamaFixesASentence() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PROOFMATE_INTEGRATION"] == "1",
            "set PROOFMATE_INTEGRATION=1 to run against a live Ollama"
        )
        let engine = OllamaEngine(settings: .defaults)
        let raw = try await engine.correct("I has a apple and she dont like it.")
        let cleaned = OutputCleaner.clean(raw, original: "I has a apple and she dont like it.")
        guard case .success(let fixed) = cleaned else {
            return XCTFail("cleaner rejected: \(raw)")
        }
        XCTAssertTrue(fixed.contains("have"), fixed)
        XCTAssertTrue(fixed.contains("an apple"), fixed)
        XCTAssertTrue(fixed.lowercased().contains("doesn't") || fixed.lowercased().contains("does not"), fixed)
    }
}

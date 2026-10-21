import XCTest
@testable import ProofMateCore

final class ModelAdvisorTests: XCTestCase {
    private func model(_ name: String) -> OllamaModel { OllamaModel(name: name, size: 1) }

    func testProseModelsAreRecommended() {
        for name in ["qwen3:8b", "qwen3:14b", "gemma3:12b", "llama3.1:8b", "mistral:7b"] {
            XCTAssertEqual(ModelAdvisor.fit(for: name), .recommended, name)
        }
    }

    func testCodeEmbeddingAndVisionModelsAreNotForProse() {
        for name in ["qwen2.5-coder:14b", "qwen3-coder:30b", "codellama:7b", "nomic-embed-text:latest", "llava:7b"] {
            XCTAssertEqual(ModelAdvisor.fit(for: name), .notForProse, name)
        }
    }

    func testUnknownModelsAreUsable() {
        for name in ["llama2:7b", "phi3:mini", "deepseek-r1:8b"] {
            XCTAssertEqual(ModelAdvisor.fit(for: name), .usable, name)
        }
    }

    func testNamespacedNamesUseTheLastPathComponent() {
        XCTAssertEqual(ModelAdvisor.fit(for: "hf.co/someone/gemma3-4b-it:Q4_K_M"), .recommended)
    }

    func testOnlyNotForProseHasANote() {
        let result = ModelAdvisor.assess([model("qwen3:8b"), model("qwen2.5-coder:14b")])
        XCTAssertNil(result[0].note)
        XCTAssertNotNil(result[1].note)
    }

    func testAssessOrdersByFitThenKeepsServerOrder() {
        let result = ModelAdvisor.assess([
            model("qwen2.5-coder:14b"), model("llama2:7b"), model("qwen3:8b"), model("gemma3:12b"),
        ])
        XCTAssertEqual(result.map(\.model.name), ["qwen3:8b", "gemma3:12b", "llama2:7b", "qwen2.5-coder:14b"])
    }
}

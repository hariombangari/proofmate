import XCTest
@testable import ProofMateCore

final class OutputCleanerTests: XCTestCase {
    private let original = "I has a apple."

    func testCleanOutputPassesThrough() {
        XCTAssertEqual(OutputCleaner.clean("I have an apple.", original: original), .success("I have an apple."))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(OutputCleaner.clean("  \nI have an apple.\n\n", original: original), .success("I have an apple."))
    }

    func testStripsPreambles() {
        let cases = [
            "Here is the corrected text: I have an apple.",
            "Here's the corrected text:\nI have an apple.",
            "Corrected text: I have an apple.",
            "Corrected: I have an apple.",
            "Sure! Here is the corrected text:\n\nI have an apple.",
        ]
        for raw in cases {
            XCTAssertEqual(OutputCleaner.clean(raw, original: original), .success("I have an apple."), raw)
        }
    }

    func testStripsWrappingQuotes() {
        XCTAssertEqual(OutputCleaner.clean("\"I have an apple.\"", original: original), .success("I have an apple."))
        XCTAssertEqual(OutputCleaner.clean("“I have an apple.”", original: original), .success("I have an apple."))
    }

    func testKeepsInternalQuotes() {
        let text = "She said \"hi\" and left."
        XCTAssertEqual(OutputCleaner.clean(text, original: text), .success(text))
    }

    func testStripsCodeFence() {
        XCTAssertEqual(OutputCleaner.clean("```\nI have an apple.\n```", original: original), .success("I have an apple."))
    }

    func testStripsThinkBlock() {
        let raw = "<think>\nThe user wrote has, should be have.\n</think>\nI have an apple."
        XCTAssertEqual(OutputCleaner.clean(raw, original: original), .success("I have an apple."))
    }

    func testEmptyIsRejected() {
        XCTAssertEqual(OutputCleaner.clean("   \n", original: original), .failure(.empty))
    }

    func testRunawayLengthIsRejected() {
        let runaway = String(repeating: "blah ", count: 50)
        XCTAssertEqual(OutputCleaner.clean(runaway, original: original), .failure(.suspiciouslyLong))
    }

    func testShortOriginalAllowsReasonableGrowth() {
        // "hi" -> "Hi." must not trip the length check.
        XCTAssertEqual(OutputCleaner.clean("Hi.", original: "hi"), .success("Hi."))
    }
}

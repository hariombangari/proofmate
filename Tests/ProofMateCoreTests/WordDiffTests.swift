import XCTest
@testable import ProofMateCore

final class WordDiffTests: XCTestCase {
    func testIdenticalTextIsOneEqualSegment() {
        XCTAssertEqual(WordDiff.diff(original: "all good here", corrected: "all good here"),
                       [.equal("all good here")])
    }

    func testSubstitutionInMiddle() {
        XCTAssertEqual(WordDiff.diff(original: "I has a apple", corrected: "I have an apple"),
                       [.equal("I"), .deleted("has a"), .inserted("have an"), .equal("apple")])
    }

    func testInsertionAtEnd() {
        XCTAssertEqual(WordDiff.diff(original: "see you", corrected: "see you soon"),
                       [.equal("see you"), .inserted("soon")])
    }

    func testDeletionAtStart() {
        XCTAssertEqual(WordDiff.diff(original: "um so hello", corrected: "hello"),
                       [.deleted("um so"), .equal("hello")])
    }

    func testEmptyOriginal() {
        XCTAssertEqual(WordDiff.diff(original: "", corrected: "hello"), [.inserted("hello")])
    }

    func testBothEmpty() {
        XCTAssertEqual(WordDiff.diff(original: "", corrected: ""), [])
    }

    func testCollapsesWhitespace() {
        XCTAssertEqual(WordDiff.diff(original: "a  b\nc", corrected: "a b c"), [.equal("a b c")])
    }
}

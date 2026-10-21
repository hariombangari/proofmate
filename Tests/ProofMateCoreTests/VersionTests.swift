import XCTest
@testable import ProofMateCore

final class VersionTests: XCTestCase {
    func testVersionIsSemver() {
        XCTAssertEqual(ProofMateVersion.current, "0.2.0")
    }
}

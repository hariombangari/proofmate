import XCTest
@testable import ProofMateCore

final class HotkeyTests: XCTestCase {
    // NSEvent.ModifierFlags raw bits, duplicated so the test needs no AppKit.
    private let shift: UInt = 1 << 17
    private let control: UInt = 1 << 18
    private let option: UInt = 1 << 19
    private let command: UInt = 1 << 20

    func testDefaultIsControlOptionG() {
        XCTAssertEqual(Hotkey.defaultCheck.keyCode, 5)
        XCTAssertEqual(Hotkey.defaultCheck.displayString, "⌃⌥G")
    }

    func testFromCocoaMapsModifiersToCarbon() throws {
        let hotkey = try XCTUnwrap(Hotkey.fromCocoa(keyCode: 5, cocoaFlags: command | shift, characters: "g"))
        XCTAssertEqual(hotkey.carbonModifiers, 256 | 512) // cmdKey | shiftKey
        XCTAssertEqual(hotkey.displayString, "⇧⌘G")
    }

    func testControlOptionMapsWithoutCommand() throws {
        let hotkey = try XCTUnwrap(Hotkey.fromCocoa(keyCode: 5, cocoaFlags: control | option, characters: "g"))
        XCTAssertEqual(hotkey.carbonModifiers, 4096 | 2048) // controlKey | optionKey
        XCTAssertEqual(hotkey, Hotkey.defaultCheck)
    }

    func testAllModifiersDisplayInMacOrder() throws {
        let hotkey = try XCTUnwrap(Hotkey.fromCocoa(
            keyCode: 40, cocoaFlags: command | shift | option | control, characters: "k"))
        XCTAssertEqual(hotkey.displayString, "⌃⌥⇧⌘K")
    }

    func testIgnoresDeviceDependentFlagBits() throws {
        let hotkey = try XCTUnwrap(Hotkey.fromCocoa(keyCode: 5, cocoaFlags: control | 0x100, characters: "g"))
        XCTAssertEqual(hotkey.carbonModifiers, 4096) // controlKey
    }

    func testRejectsShiftOnly() {
        XCTAssertNil(Hotkey.fromCocoa(keyCode: 5, cocoaFlags: shift, characters: "G"))
    }

    func testRejectsNoModifiers() {
        XCTAssertNil(Hotkey.fromCocoa(keyCode: 5, cocoaFlags: 0, characters: "g"))
    }

    func testSpaceGetsALabel() throws {
        let hotkey = try XCTUnwrap(Hotkey.fromCocoa(keyCode: 49, cocoaFlags: control | option, characters: " "))
        XCTAssertEqual(hotkey.displayString, "⌃⌥Space")
    }

    func testCodableRoundTrip() throws {
        let original = Hotkey(keyCode: 40, carbonModifiers: 256 | 2048, key: "K")
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(Hotkey.self, from: data), original)
    }

    func testIsValid() {
        XCTAssertTrue(Hotkey.defaultCheck.isValid)
        XCTAssertTrue(Hotkey(keyCode: 5, carbonModifiers: 256 | 512, key: "G").isValid)
        XCTAssertFalse(Hotkey(keyCode: 5, carbonModifiers: 512, key: "G").isValid)
        XCTAssertFalse(Hotkey(keyCode: 5, carbonModifiers: 256, key: "").isValid)
    }
}

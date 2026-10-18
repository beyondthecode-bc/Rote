import XCTest
@testable import RoteCore

final class ShortcutDecodingTests: XCTestCase {
    private func decode(_ char: String?, _ mask: Int = 0, vkey: Int = 0, glyph: Int = 0) -> ShortcutDecoding.Result {
        ShortcutDecoding.decode(cmdChar: char, modifierMask: mask, virtualKey: vkey, glyph: glyph)
    }

    func testCommandLetter() {
        XCTAssertEqual(decode("r"), .shortcut(Shortcut(modifiers: [.command], key: .character("R"))))
    }

    func testUppercaseCharacterImpliesShift() {
        XCTAssertEqual(decode("N"), .shortcut(Shortcut(modifiers: [.shift, .command], key: .character("N"))))
    }

    func testMaskCombination() {
        XCTAssertEqual(decode("v", 3), .shortcut(Shortcut(modifiers: [.shift, .option, .command], key: .character("V"))))
    }

    func testControlCommand() {
        XCTAssertEqual(decode("q", 4), .shortcut(Shortcut(modifiers: [.control, .command], key: .character("Q"))))
    }

    func testNoCommandFlag() {
        XCTAssertEqual(decode("f", 8), .shortcut(Shortcut(modifiers: [], key: .character("F"))))
    }

    func testPunctuationKeepsItself() {
        XCTAssertEqual(decode("[", 0), .shortcut(Shortcut(modifiers: [.command], key: .character("["))))
    }

    func testGlyphBackspace() {
        XCTAssertEqual(decode("\u{8}", 0, glyph: 23), .shortcut(Shortcut(modifiers: [.command], key: .special(.delete))))
    }

    func testGlyphFunctionKeysAboveTwelve() {
        // Carbon Menus.h: kMenuF12Glyph = 122, kMenuF13Glyph = 135 (0x87), kMenuF15Glyph = 137, kMenuF16Glyph = 143.
        XCTAssertEqual(decode("", 8, glyph: 122), .shortcut(Shortcut(modifiers: [], key: .special(.f12))))
        XCTAssertEqual(decode("", 8, glyph: 135), .shortcut(Shortcut(modifiers: [], key: .special(.f13))))
        XCTAssertEqual(decode("", 8, glyph: 137), .shortcut(Shortcut(modifiers: [], key: .special(.f15))))
        XCTAssertEqual(decode("", 8, glyph: 143), .shortcut(Shortcut(modifiers: [], key: .special(.f16))))
    }

    func testFunctionKeyScalar() {
        XCTAssertEqual(decode("\u{F704}", 8), .shortcut(Shortcut(modifiers: [], key: .special(.f1))))
    }

    func testArrowScalar() {
        XCTAssertEqual(decode("\u{F700}", 0), .shortcut(Shortcut(modifiers: [.command], key: .special(.upArrow))))
    }

    func testVirtualKeyFallback() {
        XCTAssertEqual(decode("", 0, vkey: 36), .shortcut(Shortcut(modifiers: [.command], key: .special(.returnKey))))
    }

    func testEmptyIsNone() {
        XCTAssertEqual(decode(""), .none)
        XCTAssertEqual(decode(nil), .none)
    }

    func testControlCharacterIsUnrenderable() {
        XCTAssertEqual(decode("\u{1}", 0), .unrenderable)
    }

    func testAXMaskDecoding() {
        XCTAssertEqual(Modifiers.fromAXMask(0), [.command])
        XCTAssertEqual(Modifiers.fromAXMask(1), [.shift, .command])
        XCTAssertEqual(Modifiers.fromAXMask(8), [])
        XCTAssertEqual(Modifiers.fromAXMask(15), [.shift, .option, .control])
    }

    func testShortcutRoundTripsThroughJSON() throws {
        let original = Shortcut(modifiers: [.option, .command], key: .special(.leftArrow))
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(Shortcut.self, from: data), original)
    }
}

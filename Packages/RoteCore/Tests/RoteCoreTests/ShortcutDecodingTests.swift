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

    func testPrintableBoundaries() {
        for value: UInt32 in [0x20, 0x7F, 0x85, 0xA0, 0xAD, 0x200B, 0x2028, 0xE000, 0xF700, 0x0301] {
            XCTAssertFalse(KeyTables.isPrintable(Unicode.Scalar(value)!), String(format: "U+%04X should not be printable", value))
        }
        for character in ["A", "[", "é", "9", "€", "ß", "あ"] {
            XCTAssertTrue(KeyTables.isPrintable(character.unicodeScalars.first!), "\(character) should be printable")
        }
    }

    func testSharpSStaysSingleScalar() {
        XCTAssertEqual(decode("ß"), .shortcut(Shortcut(modifiers: [.command], key: .character("ß"))))
        XCTAssertEqual(KeyTables.keycapCharacter(for: "ß"), "ß")
        XCTAssertEqual(KeyTables.keycapCharacter(for: "r"), "R")
        XCTAssertNil(KeyTables.keycapCharacter(for: "\u{85}"))
    }

    func testBackTabImpliesShift() {
        XCTAssertEqual(decode("\u{19}", 8), .shortcut(Shortcut(modifiers: [.shift], key: .special(.tab))))
        XCTAssertEqual(decode("", 0, glyph: 3), .shortcut(Shortcut(modifiers: [.shift, .command], key: .special(.tab))))
    }

    func testDecomposedCharacterIsPrecomposed() {
        XCTAssertEqual(decode("e\u{301}"), .shortcut(Shortcut(modifiers: [.command], key: .character("É"))))
    }

    func testC1ControlIsUnrenderable() {
        XCTAssertEqual(decode("\u{85}"), .unrenderable)
        XCTAssertEqual(decode("\u{A0}"), .unrenderable)
    }

    func testIsFunctionKey() {
        XCTAssertTrue(SpecialKey.f13.isFunctionKey)
        XCTAssertFalse(SpecialKey.forwardDelete.isFunctionKey)
        XCTAssertEqual(SpecialKey.allCases.filter(\.isFunctionKey).count, 20)
    }

    func testShortcutWireFormatIsStable() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Shortcut(modifiers: [.shift, .command], key: .character("N")))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"key":{"character":{"_0":"N"}},"modifiers":12}"#)
        let special = try encoder.encode(Shortcut(modifiers: [], key: .special(.f1)))
        XCTAssertEqual(String(decoding: special, as: UTF8.self), #"{"key":{"special":{"_0":"f1"}},"modifiers":0}"#)
    }
}

import XCTest
@testable import RoteCore

final class GlyphFormatterTests: XCTestCase {
    func testOrderIsControlOptionShiftCommand() {
        let s = Shortcut(modifiers: [.command, .shift, .option, .control], key: .character("V"))
        XCTAssertEqual(GlyphFormatter.display(s), "⌃⌥⇧⌘V")
    }

    func testSegments() {
        let s = Shortcut(modifiers: [.command], key: .character("R"))
        XCTAssertEqual(GlyphFormatter.segments(s), ["⌘", "R"])
    }

    func testSpecialSymbols() {
        XCTAssertEqual(GlyphFormatter.display(Shortcut(modifiers: [.command], key: .special(.delete))), "⌘⌫")
        XCTAssertEqual(GlyphFormatter.display(Shortcut(modifiers: [], key: .special(.f1))), "F1")
        XCTAssertEqual(GlyphFormatter.display(Shortcut(modifiers: [.command], key: .special(.returnKey))), "⌘↩")
        XCTAssertEqual(GlyphFormatter.display(Shortcut(modifiers: [.command], key: .special(.help))), "⌘Help")
    }

    func testNoSpecialKeyLooksUnrenderable() {
        for key in SpecialKey.allCases {
            let symbol = GlyphFormatter.keySymbol(.special(key))
            XCTAssertFalse(symbol.isEmpty, "\(key) has no symbol")
            XCTAssertNotEqual(symbol, GlyphFormatter.unrenderableSymbol, "\(key) collides with the unrenderable symbol")
            XCTAssertFalse(GlyphFormatter.spokenName(for: key).isEmpty, "\(key) has no spoken name")
        }
    }

    func testSpokenDescription() {
        XCTAssertEqual(GlyphFormatter.spokenDescription(Shortcut(modifiers: [.shift, .command], key: .character("N"))), "Shift Command N")
        XCTAssertEqual(GlyphFormatter.spokenDescription(Shortcut(modifiers: [.command], key: .special(.delete))), "Command Delete")
    }
}

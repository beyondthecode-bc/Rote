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
    }

    func testEverySpecialKeyHasASymbol() {
        for key in SpecialKey.allCases {
            XCTAssertFalse(GlyphFormatter.keySymbol(.special(key)).isEmpty, "\(key) has no symbol")
        }
    }

    func testSpokenDescription() {
        XCTAssertEqual(GlyphFormatter.spokenDescription(Shortcut(modifiers: [.shift, .command], key: .character("N"))), "Shift Command N")
        XCTAssertEqual(GlyphFormatter.spokenDescription(Shortcut(modifiers: [.command], key: .special(.delete))), "Command Delete")
    }
}

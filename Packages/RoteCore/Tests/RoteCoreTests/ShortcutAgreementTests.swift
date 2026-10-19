import XCTest
@testable import RoteCore

/// The Accessibility decoder and the key-press matcher are two halves of one rule: a press
/// must produce the shortcut its menu item decodes to. Each case pairs attributes as
/// Accessibility reports them (letters arrive uppercased) with the event AppKit delivers.
final class ShortcutAgreementTests: XCTestCase {
    private func item(_ char: String, mask: Int = 0, glyph: Int = 0, file: StaticString = #filePath, line: UInt = #line) -> Shortcut {
        guard case .shortcut(let shortcut) = ShortcutDecoding.decode(cmdChar: char, modifierMask: mask, virtualKey: 0, glyph: glyph) else {
            XCTFail("\(char) did not decode to a shortcut", file: file, line: line)
            return Shortcut(modifiers: [], key: .character("?"))
        }
        return shortcut
    }

    private func press(_ characters: String, command: String, keyCode: UInt16, _ modifiers: Modifiers) -> KeyPress {
        KeyPress(characters: characters, commandCharacters: command, keyCode: keyCode, modifiers: modifiers)
    }

    private func assertFires(_ shortcut: Shortcut, _ press: KeyPress, file: StaticString = #filePath, line: UInt = #line) {
        let candidates = press.candidateShortcuts
        XCTAssertTrue(
            candidates.contains(shortcut),
            "\(GlyphFormatter.display(shortcut)) is not among \(candidates.map(GlyphFormatter.display))",
            file: file, line: line
        )
    }

    func testCommandLetter() {
        assertFires(item("R"), press("r", command: "r", keyCode: 15, [.command]))
    }

    func testShiftCommandLetter() {
        assertFires(item("N", mask: 1), press("N", command: "n", keyCode: 45, [.shift, .command]))
    }

    func testOptionShiftCommandLetter() {
        assertFires(item("V", mask: 3), press("V", command: "v", keyCode: 9, [.option, .shift, .command]))
    }

    func testControlCommandLetter() {
        assertFires(item("F", mask: 4), press("f", command: "f", keyCode: 3, [.control, .command]))
    }

    func testHelpQuestionMarkTypedWithShift() {
        assertFires(item("?"), press("?", command: "/", keyCode: 44, [.shift, .command]))
    }

    func testZoomInPlusTypedWithShift() {
        assertFires(item("+"), press("+", command: "=", keyCode: 24, [.shift, .command]))
    }

    func testPunctuation() {
        assertFires(item("["), press("[", command: "[", keyCode: 33, [.command]))
    }

    func testCommandDeleteByGlyph() {
        assertFires(item("\u{8}", glyph: 23), press("\u{7F}", command: "\u{7F}", keyCode: 51, [.command]))
    }

    func testFunctionKeyWithoutModifiers() {
        assertFires(item("\u{F704}", mask: 8), press("\u{F704}", command: "", keyCode: 122, []))
    }

    func testNonLatinLayoutFiresThroughTheCommandTable() {
        assertFires(item("S"), press("ы", command: "s", keyCode: 1, [.command]))
    }

    func testShiftedLetterNeverFiresThePlainItem() {
        let candidates = press("R", command: "r", keyCode: 15, [.shift, .command]).candidateShortcuts
        XCTAssertFalse(candidates.contains(item("R")), "⇧⌘R must not count as a use of ⌘R")
    }

    func testPlainTypingFiresNothing() {
        XCTAssertTrue(press("r", command: "", keyCode: 15, []).candidateShortcuts.isEmpty)
    }

    // MARK: Observability: Rote only coaches what it can see being used (spec §5.5, §6.2 rule 3).

    func testShiftOnlyPressesAreTyping() {
        XCTAssertTrue(press("A", command: "", keyCode: 0, [.shift]).candidateShortcuts.isEmpty, "⇧A types a capital")
        XCTAssertTrue(press("\u{F703}", command: "", keyCode: 124, [.shift]).candidateShortcuts.isEmpty, "⇧→ extends a text selection")
        XCTAssertFalse(press("a", command: "", keyCode: 0, [.option]).candidateShortcuts.isEmpty, "⌥ counts as a shortcut modifier")
        XCTAssertFalse(press("\u{F708}", command: "", keyCode: 96, [.shift]).candidateShortcuts.isEmpty, "⇧F5 is still an F-key")
    }

    func testOnlyObservableShortcutsAreCoachable() {
        func record(_ shortcut: Shortcut) -> MenuItemRecord {
            MenuItemRecord(bundleID: "com.example", path: ["Menu", "Item"], shortcut: shortcut)
        }
        XCTAssertFalse(record(Shortcut(modifiers: [], key: .special(.delete))).isCoachable, "plain ⌫ looks like typing")
        XCTAssertFalse(record(Shortcut(modifiers: [.shift], key: .character("A"))).isCoachable, "⇧A looks like typing")
        XCTAssertFalse(record(Shortcut(modifiers: [.shift], key: .special(.rightArrow))).isCoachable, "⇧→ looks like typing")
        XCTAssertTrue(record(Shortcut(modifiers: [], key: .special(.f5))).isCoachable)
        XCTAssertTrue(record(Shortcut(modifiers: [.option], key: .character("A"))).isCoachable)
        XCTAssertTrue(record(item("R")).isCoachable)
    }
}

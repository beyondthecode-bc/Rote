import XCTest
@testable import RoteCore

final class KeyPressTests: XCTestCase {
    private func item(_ title: String, _ modifiers: Modifiers, _ key: Key) -> MenuItemRecord {
        MenuItemRecord(bundleID: "com.example.App", path: ["Menu", title], shortcut: Shortcut(modifiers: modifiers, key: key))
    }

    private func tree(_ items: [MenuItemRecord]) -> MenuTree {
        MenuTree(
            bundleID: "com.example.App",
            appName: "App",
            menus: [MenuTree.Menu(title: "Menu", isAppleMenu: false, items: items)],
            scannedAt: Date(timeIntervalSinceReferenceDate: 0),
            isPartial: false
        )
    }

    private func press(_ characters: String, command: String = "", keyCode: UInt16 = 1, _ modifiers: Modifiers) -> KeyPress {
        KeyPress(characters: characters, commandCharacters: command, keyCode: keyCode, modifiers: modifiers)
    }

    func testCommandLetterMatches() {
        let save = item("Save", [.command], .character("S"))
        XCTAssertEqual(tree([save]).item(for: press("s", command: "s", [.command])), save)
    }

    func testShiftedLetterNeedsTheShiftedItem() {
        let save = item("Save", [.command], .character("S"))
        let saveAs = item("Save As", [.shift, .command], .character("S"))
        XCTAssertEqual(tree([save, saveAs]).item(for: press("S", command: "s", [.shift, .command])), saveAs)
        XCTAssertNil(tree([save]).item(for: press("S", command: "s", [.shift, .command])))
    }

    func testShiftedSymbolMatchesAnItemWithoutShift() {
        // ⇧⌘/ types "?"; AppKit reports Help "⌘?" with mask 0, so the item has no ⇧.
        let help = item("Help", [.command], .character("?"))
        XCTAssertEqual(tree([help]).item(for: press("?", command: "/", keyCode: 44, [.shift, .command])), help)
        let zoomIn = item("Zoom In", [.command], .character("+"))
        XCTAssertEqual(tree([zoomIn]).item(for: press("+", command: "=", keyCode: 24, [.shift, .command])), zoomIn)
    }

    func testShiftedSymbolPrefersAnItemThatNamesTheUnshiftedKey() {
        let previousTab = item("Show Previous Tab", [.shift, .command], .character("["))
        let braceItem = item("Brace", [.command], .character("{"))
        let found = tree([braceItem, previousTab]).item(for: press("{", command: "[", keyCode: 33, [.shift, .command]))
        XCTAssertEqual(found, previousTab)
    }

    func testShiftedDigitDoesNotMatchTheUnshiftedDigit() {
        let first = item("First", [.command], .character("1"))
        XCTAssertNil(tree([first]).item(for: press("!", command: "1", keyCode: 18, [.shift, .command])))
    }

    func testCommandTableWinsOnNonLatinLayouts() {
        // Russian: the S key types "ы", but ⌘ switches to the Latin table and fires ⌘S.
        let save = item("Save", [.command], .character("S"))
        XCTAssertEqual(tree([save]).item(for: press("ы", command: "s", [.command])), save)
        XCTAssertEqual(tree([save]).item(for: press("σ", command: "s", [.command])), save)
    }

    func testDvorakQwertyCommandNeverFallsBackToTheTypedLetter() {
        // Dvorak - QWERTY ⌘: the key that types "o" fires ⌘S while ⌘ is down.
        let save = item("Save", [.command], .character("S"))
        let open = item("Open", [.command], .character("O"))
        XCTAssertEqual(tree([open, save]).item(for: press("o", command: "s", [.command])), save)
        XCTAssertNil(tree([open]).item(for: press("o", command: "s", [.command])))
    }

    func testWithoutCommandTheTypedCharacterIsUsed() {
        let item = item("Mark", [.control, .option], .character("S"))
        XCTAssertEqual(tree([item]).item(for: press("s", [.control, .option])), item)
    }

    func testCommandSharpSMatches() {
        let item = item("Sharp", [.command], .character("ß"))
        XCTAssertEqual(tree([item]).item(for: press("ß", command: "ß", keyCode: 27, [.command])), item)
    }

    func testPlainTypingMatchesNothingButFunctionKeysDo() {
        let plain = item("Plain", [], .character("S"))
        XCTAssertNil(tree([plain]).item(for: press("s", [])))
        XCTAssertTrue(press("s", []).candidateShortcuts.isEmpty)
        let fullScreen = item("Full Screen", [], .special(.f11))
        XCTAssertEqual(tree([fullScreen]).item(for: press("\u{F70E}", keyCode: 103, [])), fullScreen)
    }

    func testSpecialKeysMatchByKeyCode() {
        let back = item("Back", [.command], .special(.leftArrow))
        XCTAssertEqual(tree([back]).item(for: press("\u{F702}", command: "\u{F702}", keyCode: 123, [.command])), back)
        XCTAssertNil(tree([back]).item(for: press("\u{F702}", keyCode: 123, [])), "an arrow alone is not a shortcut")
    }

    func testCandidatesAreUniqueAndOrdered() {
        XCTAssertEqual(press("?", command: "/", keyCode: 44, [.shift, .command]).candidateShortcuts, [
            Shortcut(modifiers: [.shift, .command], key: .character("/")),
            Shortcut(modifiers: [.shift, .command], key: .character("?")),
            Shortcut(modifiers: [.command], key: .character("?")),
        ])
        XCTAssertEqual(press("s", command: "s", [.command]).candidateShortcuts, [
            Shortcut(modifiers: [.command], key: .character("S")),
        ])
    }
}

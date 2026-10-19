import XCTest
@testable import RoteCore

final class HoldDetectorTests: XCTestCase {
    func testHoldArmsFiresShowsAndReleaseHides() {
        var d = HoldDetector()
        XCTAssertEqual(d.handle(.triggerHeld), .armTimer(1))
        XCTAssertEqual(d.handle(.timerFired(1)), .show)
        XCTAssertTrue(d.isShowing)
        XCTAssertEqual(d.handle(.triggerReleased), .hide)
        XCTAssertFalse(d.isShowing)
    }

    func testKeyDownDuringHoldDisarms() {
        var d = HoldDetector()
        XCTAssertEqual(d.handle(.triggerHeld), .armTimer(1))
        XCTAssertEqual(d.handle(.keyDown), .disarmTimer)
        XCTAssertEqual(d.handle(.timerFired(1)), .none)
        XCTAssertFalse(d.isShowing)
    }

    func testMouseDownAndOtherModifiersDisarm() {
        var d = HoldDetector()
        XCTAssertEqual(d.handle(.triggerHeld), .armTimer(1))
        XCTAssertEqual(d.handle(.mouseDown), .disarmTimer)
        XCTAssertEqual(d.handle(.triggerHeld), .armTimer(2))
        XCTAssertEqual(d.handle(.otherModifierChange), .disarmTimer)
    }

    func testSecondHoldWhileArmedIsIgnored() {
        var d = HoldDetector()
        XCTAssertEqual(d.handle(.triggerHeld), .armTimer(1))
        XCTAssertEqual(d.handle(.triggerHeld), .none)
    }

    func testStaleTimerTokenIsIgnored() {
        var d = HoldDetector()
        XCTAssertEqual(d.handle(.triggerHeld), .armTimer(1))
        XCTAssertEqual(d.handle(.triggerReleased), .disarmTimer)
        XCTAssertEqual(d.handle(.triggerHeld), .armTimer(2))
        XCTAssertEqual(d.handle(.timerFired(1)), .none)
        XCTAssertEqual(d.handle(.timerFired(2)), .show)
    }

    func testKeyDownClosesTheSheet() {
        var d = HoldDetector()
        _ = d.handle(.triggerHeld)
        _ = d.handle(.timerFired(1))
        XCTAssertEqual(d.handle(.keyDown), .hide)
        XCTAssertFalse(d.isShowing)
    }

    func testStickyToggleOpensAndCloses() {
        var d = HoldDetector()
        XCTAssertEqual(d.handle(.stickyToggle), .show)
        XCTAssertTrue(d.isSticky)
        XCTAssertEqual(d.handle(.keyDown), .none)
        XCTAssertEqual(d.handle(.mouseDown), .none)
        XCTAssertEqual(d.handle(.triggerReleased), .none)
        XCTAssertEqual(d.handle(.stickyToggle), .hide)
        XCTAssertFalse(d.isShowing)
        XCTAssertFalse(d.isSticky)
    }

    func testHoldWorksAgainAfterAShowAndRelease() {
        var d = HoldDetector()
        XCTAssertEqual(d.handle(.triggerHeld), .armTimer(1))
        XCTAssertEqual(d.handle(.timerFired(1)), .show)
        XCTAssertEqual(d.handle(.triggerReleased), .hide)
        XCTAssertEqual(d.handle(.triggerHeld), .armTimer(2))
        XCTAssertEqual(d.handle(.timerFired(2)), .show)
    }

    func testClickAndOtherModifierCloseTheHeldSheet() {
        var d = HoldDetector()
        _ = d.handle(.triggerHeld)
        _ = d.handle(.timerFired(1))
        XCTAssertEqual(d.handle(.mouseDown), .hide)
        XCTAssertFalse(d.isShowing)
        _ = d.handle(.triggerHeld)
        _ = d.handle(.timerFired(2))
        XCTAssertEqual(d.handle(.otherModifierChange), .hide)
        XCTAssertFalse(d.isShowing)
    }

    func testHoldDuringStickySheetDoesNotRearm() {
        var d = HoldDetector()
        XCTAssertEqual(d.handle(.stickyToggle), .show)
        XCTAssertEqual(d.handle(.triggerHeld), .none)
        XCTAssertTrue(d.isSticky)
    }

    func testStickyHotkeyIsTheKeyThatTypesK() {
        let d = HoldDetector()
        let chord: Modifiers = [.control, .option, .command]
        func press(_ typed: String, command: String, keyCode: UInt16, _ modifiers: Modifiers = chord, isRepeat: Bool = false) -> KeyPress {
            KeyPress(characters: typed, commandCharacters: command, keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat)
        }
        // US: K is key code 40.
        XCTAssertEqual(d.input(for: press("k", command: "k", keyCode: 40)), .stickyToggle)
        // Dvorak: K is key code 9, and key code 40 types T.
        XCTAssertEqual(d.input(for: press("k", command: "k", keyCode: 9)), .stickyToggle)
        XCTAssertEqual(d.input(for: press("t", command: "t", keyCode: 40)), .keyDown)
        // Dvorak - QWERTY ⌘: the ⌘ table decides, as for every key equivalent.
        XCTAssertEqual(d.input(for: press("t", command: "k", keyCode: 40)), .stickyToggle)
        XCTAssertEqual(d.input(for: press("k", command: "v", keyCode: 9)), .keyDown)
        // Other modifiers and auto-repeats never toggle.
        XCTAssertEqual(d.input(for: press("k", command: "k", keyCode: 40, [.control, .command])), .keyDown)
        XCTAssertEqual(d.input(for: press("k", command: "k", keyCode: 40, [.control, .option, .shift, .command])), .keyDown)
        XCTAssertEqual(d.input(for: press("k", command: "k", keyCode: 40, isRepeat: true)), .keyDown)
    }

    func testEscapeClosesOnlyTheStickySheet() {
        let escape = KeyPress(characters: "\u{1B}", commandCharacters: "", keyCode: 53, modifiers: [])
        var d = HoldDetector()
        XCTAssertEqual(d.input(for: escape), .keyDown)
        _ = d.handle(.triggerHeld)
        _ = d.handle(.timerFired(1))
        XCTAssertEqual(d.input(for: escape), .keyDown)
        _ = d.handle(.triggerReleased)
        XCTAssertEqual(d.handle(.stickyToggle), .show)
        XCTAssertEqual(d.input(for: escape), .stickyToggle)
        var repeated = escape
        repeated.isRepeat = true
        XCTAssertEqual(d.input(for: repeated), .keyDown)
    }
}

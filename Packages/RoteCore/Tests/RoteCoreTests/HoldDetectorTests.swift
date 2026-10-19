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
}

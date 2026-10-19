import XCTest
@testable import RoteCore

/// One key press is one shortcut use, however late AppKit posts the selection notification
/// for its key equivalent (spec §5.5, §11).
final class ShortcutEchoFilterTests: XCTestCase {
    private static let bundleID = "com.example.editor"
    private let selectAll = item(["Edit", "Select All"], "A")
    private let copy = item(["Edit", "Copy"], "C")
    private let save = item(["File", "Save"], "S")
    private let t0 = ContinuousClock.now

    private static func item(_ path: [String], _ key: String, bundleID: String = bundleID) -> MenuItemRecord {
        MenuItemRecord(bundleID: bundleID, path: path, shortcut: Shortcut(modifiers: [.command], key: .character(key)))
    }

    private func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        t0 + .milliseconds(milliseconds)
    }

    func testEchoOfASlowActionIsDroppedSecondsLater() {
        var filter = ShortcutEchoFilter()
        XCTAssertTrue(filter.keyPressMatched(save, at: at(0)))
        XCTAssertTrue(filter.isEcho(save, at: at(1_200)))
        XCTAssertFalse(filter.isEcho(save, at: at(1_300)), "one press pairs with one notification")
    }

    func testQuickPressesOfDifferentShortcutsPairWithTheirOwnEchoes() {
        var filter = ShortcutEchoFilter()
        XCTAssertTrue(filter.keyPressMatched(selectAll, at: at(0)))
        XCTAssertTrue(filter.keyPressMatched(copy, at: at(40)))
        XCTAssertTrue(filter.isEcho(selectAll, at: at(600)))
        XCTAssertTrue(filter.isEcho(copy, at: at(600)))
    }

    func testRepeatedPressesAllCount() {
        var filter = ShortcutEchoFilter()
        for step in 0..<3 {
            XCTAssertTrue(filter.keyPressMatched(save, at: at(step * 120)), "press \(step + 1)")
        }
        for _ in 0..<3 {
            XCTAssertTrue(filter.isEcho(save, at: at(400)))
        }
        XCTAssertFalse(filter.isEcho(save, at: at(400)))
    }

    /// The scan saw "Undo Typing"; by the time ⌘Z fires, the item reads "Undo Paste".
    func testEchoWithAChangedTitlePairsByShortcutInTheSameApp() {
        var filter = ShortcutEchoFilter()
        let undoTyping = Self.item(["Edit", "Undo Typing"], "Z")
        let undoPaste = Self.item(["Edit", "Undo Paste"], "Z")
        XCTAssertTrue(filter.keyPressMatched(undoTyping, at: at(0)))
        XCTAssertFalse(filter.isEcho(Self.item(["Edit", "Undo Paste"], "Z", bundleID: "com.example.other"), at: at(50)), "another app's item")
        XCTAssertFalse(filter.isEcho(Self.item(["Edit", "Redo"], "Y"), at: at(50)), "another shortcut")
        XCTAssertTrue(filter.isEcho(undoPaste, at: at(50)))
    }

    func testItemsWithoutShortcutPairOnlyByIdentity() {
        var filter = ShortcutEchoFilter()
        let first = MenuItemRecord(bundleID: Self.bundleID, path: ["View", "One"], shortcut: nil)
        let second = MenuItemRecord(bundleID: Self.bundleID, path: ["View", "Two"], shortcut: nil)
        XCTAssertTrue(filter.keyPressMatched(first, at: at(0)))
        XCTAssertFalse(filter.isEcho(second, at: at(10)))
        XCTAssertTrue(filter.isEcho(first, at: at(10)))
    }

    func testAPressWaitsAtMostTheEchoTimeout() {
        var filter = ShortcutEchoFilter()
        XCTAssertTrue(filter.keyPressMatched(save, at: at(0)))
        XCTAssertFalse(filter.isEcho(save, at: t0 + ShortcutEchoFilter.echoTimeout + .milliseconds(1)))
    }

    func testASelectionWithNoPressIsNotAnEcho() {
        var filter = ShortcutEchoFilter()
        XCTAssertFalse(filter.isEcho(save, at: at(0)))
        XCTAssertFalse(filter.isEcho(save, at: at(120)))
    }

    /// The notification can beat the key monitor; the press that follows is the same use.
    func testAPressRightAfterItsCountedSelectionIsDropped() {
        var filter = ShortcutEchoFilter()
        filter.selectionCounted(save, at: at(0))
        XCTAssertFalse(filter.keyPressMatched(save, at: at(100)))
        XCTAssertTrue(filter.keyPressMatched(save, at: at(150)), "the selection paired with one press only")
        XCTAssertTrue(filter.isEcho(save, at: at(400)), "and that press now waits for its own echo")
    }

    func testASelectionWaitsForItsPressOnlyBriefly() {
        var filter = ShortcutEchoFilter()
        filter.selectionCounted(save, at: at(0))
        XCTAssertTrue(filter.keyPressMatched(save, at: t0 + ShortcutEchoFilter.earlyEchoWindow + .milliseconds(1)))
    }

    func testResetForgetsEverythingPending() {
        var filter = ShortcutEchoFilter()
        XCTAssertTrue(filter.keyPressMatched(save, at: at(0)))
        filter.selectionCounted(copy, at: at(0))
        filter.reset()
        XCTAssertFalse(filter.isEcho(save, at: at(50)))
        XCTAssertTrue(filter.keyPressMatched(copy, at: at(50)))
    }
}

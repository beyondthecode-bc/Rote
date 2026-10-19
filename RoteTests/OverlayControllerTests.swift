import XCTest
@testable import Rote
import RoteAX
import RoteCore

/// The sheet's triggers and closing rules, with the overlay wired to a harness engine the way
/// `AppContainer` wires the real one. The panel never goes on screen.
@MainActor
final class OverlayControllerTests: XCTestCase {
    private let save = Fixtures.item(["File", "Save"], "S")
    private let hotkey = KeyPress(characters: "k", commandCharacters: "k", keyCode: 40, modifiers: [.control, .option, .command])
    private let escape = KeyPress(characters: "\u{1B}", commandCharacters: "", keyCode: 53, modifiers: [])
    private let pressS = Fixtures.commandPress("s", keyCode: 1)

    private func makeOverlay(_ trigger: AppSettings.OverlayTrigger) async throws -> (EngineHarness, OverlayController) {
        let harness = try EngineHarness()
        addTeardownBlock { @MainActor in await harness.tearDown() }
        harness.settings.overlayTrigger = trigger
        harness.settings.holdDelayMs = 10
        let overlay = OverlayController(settings: harness.settings, engine: harness.engine, presentsPanel: false)
        AppContainer.connect(overlay, to: harness.engine)
        await harness.engine.start()
        await harness.activate(Fixtures.appA, serving: Fixtures.tree([Fixtures.menu("File", [save])]))
        return (harness, overlay)
    }

    /// A modifier change or a click, as the key monitor reports it.
    private func send(_ event: KeyEventMonitor.Event, to h: EngineHarness) {
        h.keyMonitor.onEvent?(event)
    }

    private func assertClosed(_ h: EngineHarness, _ overlay: OverlayController, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(overlay.isShowing, message, file: file, line: line)
        XCTAssertFalse(h.engine.overlayVisible, message, file: file, line: line)
        XCTAssertNil(overlay.presentedTree, message, file: file, line: line)
    }

    // MARK: The sticky hotkey follows the trigger setting

    func testWithAHoldTriggerTheStickyHotkeyNeverOpensTheSheet() async throws {
        for trigger in [AppSettings.OverlayTrigger.holdCommand, .holdOption] {
            let (h, overlay) = try await makeOverlay(trigger)
            h.press(hotkey)
            assertClosed(h, overlay, "\(trigger)")
            h.press(hotkey)
            assertClosed(h, overlay, "\(trigger): a second press opens nothing either")
            XCTAssertFalse(overlay.hasShownOnce, "\(trigger)")
        }
    }

    /// With hold-⌘ chosen, ⌃⌥⌘K is a key like any other: it cancels a hold that is waiting.
    func testWithAHoldTriggerTheStickyHotkeyCancelsAHoldLikeAnyKey() async throws {
        let (h, overlay) = try await makeOverlay(.holdCommand)
        send(.flagsChanged(modifiers: [.command]), to: h)
        h.press(hotkey)
        try await Task.sleep(for: .milliseconds(60))      // past the 10 ms hold delay
        assertClosed(h, overlay)
    }

    func testWithTheStickyTriggerTheHotkeyOpensAndClosesTheSheet() async throws {
        let (h, overlay) = try await makeOverlay(.stickyHotkey)
        h.press(hotkey)
        XCTAssertTrue(overlay.isShowing)
        XCTAssertTrue(h.engine.overlayVisible)
        XCTAssertEqual(overlay.presentedTree?.bundleID, Fixtures.appA.bundleID)
        XCTAssertTrue(overlay.hasShownOnce)

        h.press(hotkey)
        assertClosed(h, overlay)
    }

    func testEscClosesAStickySheetAndOtherKeysAndClicksDoNot() async throws {
        let (h, overlay) = try await makeOverlay(.stickyHotkey)
        h.press(hotkey)
        h.press(pressS)
        send(.mouseDown, to: h)
        send(.flagsChanged(modifiers: [.command]), to: h)
        send(.flagsChanged(modifiers: []), to: h)
        XCTAssertTrue(overlay.isShowing)

        h.press(escape)
        assertClosed(h, overlay)
    }

    /// The trigger changed while a sticky sheet was up: Esc and the hotkey still close it.
    func testAStickySheetLeftUpAfterTheTriggerChangesStillCloses() async throws {
        let (h, overlay) = try await makeOverlay(.stickyHotkey)
        h.press(hotkey)
        h.settings.overlayTrigger = .holdCommand
        h.press(hotkey)
        assertClosed(h, overlay, "the hotkey")

        h.settings.overlayTrigger = .stickyHotkey
        h.press(hotkey)
        h.settings.overlayTrigger = .holdOption
        h.press(escape)
        assertClosed(h, overlay, "Esc")
    }

    // MARK: Closing on an app switch

    func testAStickySheetClosesWhenTheFrontmostAppChanges() async throws {
        let (h, overlay) = try await makeOverlay(.stickyHotkey)
        for next in [Fixtures.appB, Fixtures.ownApp, nil] as [AppIdentity?] {
            let name = next?.bundleID ?? "an app without a bundle ID"
            h.activate(Fixtures.appA)             // its tree is cached
            h.press(hotkey)                       // opens: the last switch left no sticky state behind
            XCTAssertTrue(overlay.isShowing, name)

            h.activate(next)
            assertClosed(h, overlay, name)
        }
    }

    func testAHeldSheetClosesWhenTheFrontmostAppChanges() async throws {
        let (h, overlay) = try await makeOverlay(.holdCommand)
        send(.flagsChanged(modifiers: [.command]), to: h)
        await waitUntil { overlay.isShowing }

        h.activate(Fixtures.appB)
        assertClosed(h, overlay)
        send(.flagsChanged(modifiers: []), to: h)
        assertClosed(h, overlay)
    }

    // MARK: The Debug menu's simulated sheet

    #if DEBUG
    func testSimulateShowsTheFixtureUntilTheNextKey() async throws {
        let (h, overlay) = try await makeOverlay(.holdCommand)
        overlay.simulate()
        XCTAssertTrue(overlay.isShowing)
        XCTAssertEqual(overlay.presentedTree, OverlayFixture.tree)
        XCTAssertTrue(h.engine.overlayVisible)
        XCTAssertTrue(overlay.hasShownOnce)

        send(.flagsChanged(modifiers: [.command]), to: h)
        send(.flagsChanged(modifiers: []), to: h)
        XCTAssertTrue(overlay.isShowing, "modifiers alone keep it up, as on a sticky sheet")

        h.press(pressS)
        assertClosed(h, overlay)
    }

    func testASimulatedSheetClosesOnEscAClickOrAnAppSwitch() async throws {
        let (h, overlay) = try await makeOverlay(.holdCommand)
        overlay.simulate()
        XCTAssertEqual(overlay.presentedTree, OverlayFixture.tree)
        h.press(escape)
        assertClosed(h, overlay, "Esc")

        overlay.simulate()
        XCTAssertEqual(overlay.presentedTree, OverlayFixture.tree)
        send(.mouseDown, to: h)
        assertClosed(h, overlay, "a click")

        overlay.simulate()
        XCTAssertEqual(overlay.presentedTree, OverlayFixture.tree)
        h.activate(Fixtures.appB)
        assertClosed(h, overlay, "an app switch")
    }

    /// Closing on any key belongs to the simulated sheet only: once it has closed, a key or a click
    /// opens nothing, and a real sticky sheet ignores both again. Each is checked on its own, since a
    /// key and a click that both toggled the sheet would cancel out.
    func testAfterASimulatedSheetARealStickySheetIgnoresKeysAndClicksAgain() async throws {
        let (h, overlay) = try await makeOverlay(.stickyHotkey)
        overlay.simulate()
        XCTAssertEqual(overlay.presentedTree, OverlayFixture.tree)
        send(.mouseDown, to: h)
        assertClosed(h, overlay)

        h.press(pressS)
        assertClosed(h, overlay, "a key with no sheet up")
        send(.mouseDown, to: h)
        assertClosed(h, overlay, "a click with no sheet up")

        h.press(hotkey)
        XCTAssertEqual(overlay.presentedTree?.bundleID, Fixtures.appA.bundleID)
        h.press(pressS)
        XCTAssertTrue(overlay.isShowing, "a key")
        send(.mouseDown, to: h)
        XCTAssertTrue(overlay.isShowing, "a click")

        h.press(escape)
        assertClosed(h, overlay)
    }

    func testSimulateWhileASheetIsUpChangesNothing() async throws {
        let (h, overlay) = try await makeOverlay(.stickyHotkey)
        h.press(hotkey)
        overlay.simulate()
        XCTAssertEqual(overlay.presentedTree?.bundleID, Fixtures.appA.bundleID)
        h.press(pressS)
        XCTAssertTrue(overlay.isShowing, "still the real sticky sheet")
    }

    func testTheFixtureCoversWhatTheSheetDraws() {
        let tree = OverlayFixture.tree
        XCTAssertTrue((3...4).contains(tree.menus.count), "\(tree.menus.count) menus")
        XCTAssertFalse(OverlayFixture.coaching.isEmpty)
        XCTAssertFalse(OverlayFixture.learned.isEmpty)
        XCTAssertTrue(OverlayFixture.coaching.isDisjoint(with: OverlayFixture.learned))
        for identity in OverlayFixture.coaching.union(OverlayFixture.learned) {
            XCTAssertNotNil(tree.allItems.first { $0.identity == identity && $0.shortcut != nil }, identity)
        }
        XCTAssertTrue(tree.allItems.contains { !$0.parentPath.isEmpty && $0.shortcut != nil }, "a submenu item")
        XCTAssertTrue(tree.allItems.contains { $0.title.count >= 40 && $0.shortcut != nil }, "a long title")
    }
    #endif
}

import XCTest
@testable import Rote
import RoteAX
import RoteCore

/// Menu notifications, key presses and activations in, coach decisions and the tree cache out.
@MainActor
final class CoachEngineEventTests: XCTestCase {
    private let save = Fixtures.item(["File", "Save"], "S")
    private let copy = Fixtures.item(["Edit", "Copy"], "C")
    private let paste = Fixtures.item(["Edit", "Paste"], "V")
    private let zoom = Fixtures.item(["View", "Zoom In"], "+")
    private let pressS = Fixtures.commandPress("s", keyCode: 1)

    private func makeHarness(menuCloseGrace: Duration = .milliseconds(300)) async throws -> EngineHarness {
        let harness = try EngineHarness(menuCloseGrace: menuCloseGrace)
        addTeardownBlock { @MainActor in await harness.tearDown() }
        await harness.engine.start()
        return harness
    }

    /// One instance per test: a tree's scan time is part of its equality.
    private lazy var treeA = Fixtures.tree([Fixtures.menu("File", [save]), Fixtures.menu("Edit", [copy])])

    // MARK: Menu versus shortcut use

    func testThreeMousePicksNudgeOnceAndCountAsMenuUses() async throws {
        let h = try await makeHarness()
        await h.activate(Fixtures.appA, serving: treeA)

        h.menuPick(save)
        h.menuPick(save)
        XCTAssertTrue(h.nudges.isEmpty)
        XCTAssertFalse(h.engine.nudgeOnScreen)
        h.menuPick(save)

        XCTAssertEqual(h.nudges.map(\.identity), [save.identity])
        XCTAssertTrue(h.engine.nudgeOnScreen)
        XCTAssertEqual(h.record(save)?.menuUses.count, 3)
        XCTAssertEqual(h.record(save)?.phase, .coaching)

        h.engine.nudgeDismissed()
        XCTAssertFalse(h.engine.nudgeOnScreen)
    }

    func testAMenuIsOpenUntilEveryOpenedMenuCloses() async throws {
        let h = try await makeHarness()
        await h.activate(Fixtures.appA, serving: treeA)
        XCTAssertFalse(h.engine.isMenuOpen)
        h.send(.menuOpened)
        h.send(.menuOpened)               // a submenu
        h.send(.menuClosed)
        XCTAssertTrue(h.engine.isMenuOpen)
        h.send(.menuClosed)
        XCTAssertFalse(h.engine.isMenuOpen)
        h.send(.menuClosed)               // an unmatched close never goes below zero
        h.send(.menuOpened)
        XCTAssertTrue(h.engine.isMenuOpen)
    }

    func testASelectionJustAfterTheMenuClosedIsStillAMenuUse() async throws {
        let h = try await makeHarness()
        await h.activate(Fixtures.appA, serving: treeA)
        h.coach(save)

        h.send(.menuOpened)
        h.send(.menuClosed)
        h.send(.itemSelected(save))       // AppKit can report the pick after the close

        XCTAssertEqual(h.record(save)?.menuUses.count, 4)
        XCTAssertEqual(h.record(save)?.shortcutUses.count, 0)
    }

    func testASelectionOnceTheCloseGraceHasPassedIsAShortcutUse() async throws {
        let h = try await makeHarness(menuCloseGrace: .milliseconds(50))
        await h.activate(Fixtures.appA, serving: treeA)
        h.coach(save)

        h.send(.menuOpened)
        h.send(.menuClosed)
        try await Task.sleep(for: .milliseconds(80))
        h.send(.itemSelected(save))

        XCTAssertEqual(h.record(save)?.menuUses.count, 3)
        XCTAssertEqual(h.record(save)?.shortcutUses.count, 1)
        XCTAssertEqual(h.record(save)?.shortcutUsesSinceCoaching, 1)
    }

    // MARK: One key press, one use

    func testAKeyPressAndItsSelectionEchoCountOnce() async throws {
        let h = try await makeHarness()
        await h.activate(Fixtures.appA, serving: treeA)
        h.coach(save)

        h.press(pressS)
        XCTAssertEqual(h.record(save)?.shortcutUses.count, 1)
        h.send(.itemSelected(save))       // the app's notification for the same key equivalent
        XCTAssertEqual(h.record(save)?.shortcutUses.count, 1)
        XCTAssertEqual(h.record(save)?.menuUses.count, 3)
    }

    func testAnEchoArrivingBeforeItsKeyPressCountsOnce() async throws {
        let h = try await makeHarness(menuCloseGrace: .milliseconds(50))
        await h.activate(Fixtures.appA, serving: treeA)
        h.coach(save)
        try await Task.sleep(for: .milliseconds(80))

        h.send(.itemSelected(save))       // no menu involved: counted as the shortcut use
        XCTAssertEqual(h.record(save)?.shortcutUses.count, 1)
        h.press(pressS)                   // the press behind it
        XCTAssertEqual(h.record(save)?.shortcutUses.count, 1)
    }

    func testRepeatedPressesWithTheirEchoesEachCountAndTeachTheShortcut() async throws {
        let h = try await makeHarness()
        await h.activate(Fixtures.appA, serving: treeA)
        h.coach(save)

        for _ in 0..<3 {
            h.press(pressS)
            h.send(.itemSelected(save))
        }

        XCTAssertEqual(h.record(save)?.shortcutUses.count, 3)
        XCTAssertEqual(h.record(save)?.phase, .learned)
    }

    func testOpeningAMenuForgetsAPressStillWaitingForItsEcho() async throws {
        let h = try await makeHarness()
        await h.activate(Fixtures.appA, serving: treeA)
        h.coach(save)

        h.press(pressS)
        h.menuPick(save)                  // a later pick is a pick, not the press's echo

        XCTAssertEqual(h.record(save)?.shortcutUses.count, 1)
        XCTAssertEqual(h.record(save)?.menuUses.count, 4)
    }

    func testAutoRepeatsOwnAppPressesAndPressesWithoutATreeAreNotShortcutUses() async throws {
        let h = try await makeHarness()
        await h.activate(Fixtures.appA, serving: treeA)
        h.coach(save)

        h.press(Fixtures.commandPress("s", keyCode: 1, isRepeat: true))
        h.press(pressS, inOwnApp: true)
        XCTAssertEqual(h.record(save)?.shortcutUses.count, 0)

        h.activate(nil)
        h.press(pressS)
        XCTAssertEqual(h.record(save)?.shortcutUses.count, 0)
    }

    func testEveryKeyEventReachesTheOverlay() async throws {
        let h = try await makeHarness()
        let repeatPress = Fixtures.commandPress("s", keyCode: 1, isRepeat: true)
        h.press(pressS, inOwnApp: true)
        h.press(repeatPress)
        h.keyMonitor.onEvent?(.flagsChanged(modifiers: [.command]))
        h.keyMonitor.onEvent?(.mouseDown)

        XCTAssertEqual(h.keyEvents, [
            .keyDown(pressS, inOwnApp: true),
            .keyDown(repeatPress, inOwnApp: false),
            .flagsChanged(modifiers: [.command]),
            .mouseDown,
        ])
    }

    // MARK: Coaching context

    func testExcludedAppsAreIgnoredAndPausedAppsAreRecordedWithoutNudges() async throws {
        let h = try await makeHarness()
        h.settings.excludedBundleIDs = [Fixtures.appA.bundleID]
        h.settings.pausedBundleIDs = [Fixtures.appB.bundleID]
        let open = Fixtures.item(Fixtures.appB, ["File", "Open"], "O")

        await h.activate(Fixtures.appA, serving: treeA)
        for _ in 0..<3 { h.menuPick(save) }
        XCTAssertNil(h.record(save))

        await h.activate(Fixtures.appB, serving: Fixtures.tree(Fixtures.appB, [Fixtures.menu("File", [open])]))
        for _ in 0..<3 { h.menuPick(open) }
        XCTAssertEqual(h.record(open)?.menuUses.count, 3)
        XCTAssertTrue(h.nudges.isEmpty)
    }

    func testNoNudgeWhileTheOverlayIsVisible() async throws {
        let h = try await makeHarness()
        await h.activate(Fixtures.appA, serving: treeA)
        h.engine.overlayVisible = true
        for _ in 0..<3 { h.menuPick(save) }
        XCTAssertTrue(h.nudges.isEmpty)
        XCTAssertEqual(h.record(save)?.menuUses.count, 3)

        h.engine.overlayVisible = false
        h.menuPick(save)
        XCTAssertEqual(h.nudges.map(\.identity), [save.identity])
    }

    func testNoNudgeWhileAnotherNudgeIsOnScreen() async throws {
        let h = try await makeHarness()
        await h.activate(Fixtures.appA, serving: treeA)
        h.engine.nudgeOnScreen = true
        for _ in 0..<3 { h.menuPick(save) }
        XCTAssertTrue(h.nudges.isEmpty)
        XCTAssertEqual(h.record(save)?.menuUses.count, 3)

        h.engine.nudgeDismissed()
        h.menuPick(save)
        XCTAssertEqual(h.nudges.map(\.identity), [save.identity])
    }

    func testANudgeIsSavedToTheStateFile() async throws {
        let h = try await makeHarness()
        await h.activate(Fixtures.appA, serving: treeA)
        for _ in 0..<3 { h.menuPick(save) }

        await waitUntil { await h.savedState()?.items[self.save.identity]?.phase == .coaching }
    }

    func testSnoozeMuteAndUnmuteChangeTheRecordAndAreSaved() async throws {
        let h = try await makeHarness()
        await h.activate(Fixtures.appA, serving: treeA)
        h.coach(save)

        h.engine.snooze(save.identity)
        let until = try XCTUnwrap(h.record(save)?.snoozedUntil)
        XCTAssertEqual(until.timeIntervalSinceNow, 7 * 86_400, accuracy: 60)
        await waitUntil { await h.savedState()?.items[self.save.identity]?.snoozedUntil != nil }

        h.engine.mute(save.identity)
        XCTAssertEqual(h.record(save)?.phase, .muted)
        await waitUntil { await h.savedState()?.items[self.save.identity]?.phase == .muted }

        h.engine.unmute(save.identity)
        XCTAssertEqual(h.record(save)?.phase, .observed)
        await waitUntil { await h.savedState()?.items[self.save.identity]?.phase == .observed }
    }

    // MARK: Activations

    func testActivatingAnAppAttachesTheObserverAndScansIt() async throws {
        let h = try await makeHarness()
        await h.activate(Fixtures.appA, serving: treeA)

        XCTAssertEqual(h.engine.currentApp, Fixtures.appA)
        XCTAssertEqual(h.observer.attachedApp, Fixtures.appA)
        let scans = await h.scanner.scans
        XCTAssertEqual(scans, [Fixtures.appA.bundleID])
    }

    func testANilActivationStopsCoachingThePreviousApp() async throws {
        let h = try await makeHarness()
        await h.activate(Fixtures.appA, serving: treeA)
        h.send(.menuOpened)

        h.activate(nil)

        XCTAssertNil(h.engine.currentApp)
        XCTAssertNil(h.engine.currentTree)
        XCTAssertNil(h.observer.attachedApp)
        XCTAssertFalse(h.engine.isMenuOpen)
    }

    func testRoteInFrontKeepsThePreviousAppsSheetButStopsObserving() async throws {
        let h = try await makeHarness()
        await h.activate(Fixtures.appA, serving: treeA)
        h.send(.menuOpened)

        h.activate(Fixtures.ownApp)
        await settle()

        XCTAssertEqual(h.engine.currentApp, Fixtures.appA)
        XCTAssertEqual(h.engine.currentTree, treeA)
        XCTAssertNil(h.observer.attachedApp)
        XCTAssertFalse(h.engine.isMenuOpen)
        let ownScans = await h.scanner.scanCount(Fixtures.ownApp.bundleID)
        XCTAssertEqual(ownScans, 0)
    }

    func testAnActivationForgetsAPressStillWaitingForItsEcho() async throws {
        let h = try await makeHarness(menuCloseGrace: .milliseconds(50))
        await h.activate(Fixtures.appA, serving: treeA)
        h.coach(save)
        try await Task.sleep(for: .milliseconds(80))
        h.press(pressS)
        XCTAssertEqual(h.record(save)?.shortcutUses.count, 1)

        h.activate(Fixtures.ownApp)
        h.activate(Fixtures.appA)         // cached: same tree, no rescan
        h.send(.itemSelected(save))       // not the old press's echo: a use of its own

        XCTAssertEqual(h.record(save)?.shortcutUses.count, 2)
        XCTAssertEqual(h.record(save)?.menuUses.count, 3)
    }

    // MARK: Tree cache

    func testAFreshCompleteTreeIsReusedOnTheNextActivation() async throws {
        let h = try await makeHarness()
        await h.activate(Fixtures.appA, serving: treeA)
        await h.activate(Fixtures.appB, serving: Fixtures.tree(Fixtures.appB, []))

        h.activate(Fixtures.appA)
        XCTAssertEqual(h.engine.currentTree, treeA)
        await settle()
        let scans = await h.scanner.scanCount(Fixtures.appA.bundleID)
        XCTAssertEqual(scans, 1)
    }

    func testAKnownItemDoesNotRescanButAnUnknownOneMergesAPartialScanOverTheCache() async throws {
        let h = try await makeHarness()
        await h.activate(Fixtures.appA, serving: treeA)

        h.menuPick(copy)
        await settle()
        var scans = await h.scanner.scanCount(Fixtures.appA.bundleID)
        XCTAssertEqual(scans, 1, "an item the tree has needs no rescan")

        // The rescan reads Edit in full, then runs out of time inside View.
        let partial = Fixtures.tree(
            [Fixtures.menu("Edit", [copy, paste]), Fixtures.menu("View", [zoom], complete: false)],
            partial: true
        )
        await h.scanner.enqueue(partial)
        h.menuPick(paste)
        await waitUntil { h.engine.currentTree?.isPartial == true }

        let tree = try XCTUnwrap(h.engine.currentTree)
        XCTAssertEqual(tree.menus.map(\.title), ["Edit", "File", "View"])
        XCTAssertTrue(tree.contains(identity: paste.identity))
        XCTAssertTrue(tree.contains(identity: save.identity), "the cached File menu survives the partial scan")
        XCTAssertEqual(h.record(paste)?.menuUses.count, 1, "the unknown item still counts")

        // A partial tree is rescanned on the next activation.
        h.activate(Fixtures.appB)
        h.activate(Fixtures.appA)
        XCTAssertEqual(h.engine.currentTree, tree, "the cached tree serves until the rescan lands")
        await waitUntil { await h.scanner.scanCount(Fixtures.appA.bundleID) == 3 }
        await waitUntil { h.engine.currentTree?.isPartial == false }
        scans = await h.scanner.scanCount(Fixtures.appA.bundleID)
        XCTAssertEqual(scans, 3)
    }

    func testAnActivationDuringAScanStartsNoSecondScan() async throws {
        let h = try await makeHarness()
        await h.scanner.hold()
        await h.scanner.enqueue(treeA)
        h.activate(Fixtures.appA)
        await waitUntil { await h.scanner.scanCount(Fixtures.appA.bundleID) == 1 }

        h.activate(nil)
        h.activate(Fixtures.appA)
        await settle()
        await h.scanner.release()
        await waitUntil { h.engine.currentTree == self.treeA }

        let scans = await h.scanner.scanCount(Fixtures.appA.bundleID)
        XCTAssertEqual(scans, 1)
    }

    func testAScanThatFinishesAfterSwitchingAppsIsCachedButNotShown() async throws {
        let h = try await makeHarness()
        let treeB = Fixtures.tree(Fixtures.appB, [Fixtures.menu("Go", [Fixtures.item(Fixtures.appB, ["Go", "Back"], "[")])])
        await h.scanner.hold()
        await h.scanner.enqueue(treeA)
        await h.scanner.enqueue(treeB)
        h.activate(Fixtures.appA)
        h.activate(Fixtures.appB)
        await waitUntil { await h.scanner.scans.count == 2 }

        await h.scanner.release(Fixtures.appB.bundleID)
        await waitUntil { h.engine.currentTree == treeB }
        await h.scanner.release(Fixtures.appA.bundleID)   // A's scan lands while B is in front
        await waitUntil { await h.scanner.scanCount(Fixtures.appA.bundleID) == 1 }
        await settle()
        XCTAssertEqual(h.engine.currentTree, treeB)

        h.activate(Fixtures.appA)
        XCTAssertEqual(h.engine.currentTree, treeA, "A's scan was cached")
        await settle()
        let scansOfA = await h.scanner.scanCount(Fixtures.appA.bundleID)
        XCTAssertEqual(scansOfA, 1)
    }

    func testTheTreeCacheKeepsTheTwentyMostRecentApps() async throws {
        let h = try await makeHarness()
        let apps = (0..<21).map { AppIdentity(pid: pid_t(91_000 + $0), bundleID: "com.example.App\($0)", name: "App \($0)") }
        for app in apps {
            await h.activate(app, serving: Fixtures.tree(app, []))
        }

        h.activate(apps[20])
        h.activate(apps[1])
        await settle()
        var newest = await h.scanner.scanCount(apps[20].bundleID)
        var second = await h.scanner.scanCount(apps[1].bundleID)
        XCTAssertEqual(newest, 1)
        XCTAssertEqual(second, 1)

        h.activate(apps[0])               // the oldest was evicted
        await waitUntil { await h.scanner.scanCount(apps[0].bundleID) == 2 }
        await waitUntil { h.engine.currentTree?.bundleID == apps[0].bundleID }
        newest = await h.scanner.scanCount(apps[20].bundleID)
        second = await h.scanner.scanCount(apps[1].bundleID)
        XCTAssertEqual(newest, 1)
        XCTAssertEqual(second, 1)
    }
}

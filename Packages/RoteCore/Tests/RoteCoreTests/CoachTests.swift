import XCTest
@testable import RoteCore

final class CoachTests: XCTestCase {
    /// Shared fixtures (CoachTestSupport.swift), spelled short.
    private typealias Fx = CoachFixtures

    func testThirdMenuUseNudges() {
        var state = CoachState()
        let c = Fx.coach()
        XCTAssertEqual(c.handle(Fx.menu(Fx.reload, at: 0), state: &state, context: Fx.ctx), .record)
        XCTAssertEqual(c.handle(Fx.menu(Fx.reload, at: 60), state: &state, context: Fx.ctx), .record)
        guard case .nudge(let record) = c.handle(Fx.menu(Fx.reload, at: 120), state: &state, context: Fx.ctx) else {
            return XCTFail("expected a nudge on the third use")
        }
        XCTAssertEqual(record.phase, .coaching)
        XCTAssertEqual(record.nudgeCount, 1)
        XCTAssertEqual(record.menuUsesSinceLastNudge, 0)
        XCTAssertEqual(state.nudgesByDay["2026-10-12"], 1)
        XCTAssertEqual(state.log.count, 3)
    }

    func testItemsWithoutShortcutAreIgnored() {
        var state = CoachState()
        var noShortcut = Fx.reload
        noShortcut.shortcut = nil
        XCTAssertEqual(Fx.coach().handle(Fx.menu(noShortcut, at: 0), state: &state, context: Fx.ctx), .ignore)
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertTrue(state.log.isEmpty)
    }

    func testOwnAppAndExcludedAppsAreIgnored() {
        var state = CoachState()
        let own = MenuItemRecord(bundleID: "com.beyondthecode.rote", path: ["Rote", "Quit"], shortcut: Shortcut(modifiers: [.command], key: .character("Q")))
        XCTAssertEqual(Fx.coach().handle(Fx.menu(own, at: 0), state: &state, context: Fx.ctx), .ignore)
        var excluded = Fx.ctx
        excluded.isAppExcluded = true
        XCTAssertEqual(Fx.coach().handle(Fx.menu(Fx.reload, at: 0), state: &state, context: excluded), .ignore)
        XCTAssertTrue(state.items.isEmpty)
    }

    func testPausedRecordsWithoutNudge() {
        var state = CoachState()
        var paused = Fx.ctx
        paused.isPaused = true
        XCTAssertEqual(Fx.use(Fx.reload, times: 3, from: 0, coach: Fx.coach(), state: &state, context: paused), .record)
        XCTAssertEqual(state.items[Fx.reload.identity]?.phase, .observed)
        XCTAssertEqual(state.items[Fx.reload.identity]?.menuUses.count, 3)
    }

    func testNudgeOnScreenOrOverlayBlocks() {
        var state = CoachState()
        var busy = Fx.ctx
        busy.isNudgeOnScreen = true
        XCTAssertEqual(Fx.use(Fx.reload, times: 3, from: 0, coach: Fx.coach(), state: &state, context: busy), .record)
        busy.isNudgeOnScreen = false
        busy.isOverlayVisible = true
        XCTAssertEqual(Fx.coach().handle(Fx.menu(Fx.reload, at: 100), state: &state, context: busy), .record)
        // The next free moment nudges: count since last nudge is already past the threshold.
        guard case .nudge = Fx.coach().handle(Fx.menu(Fx.reload, at: 200), state: &state, context: Fx.ctx) else {
            return XCTFail("expected a nudge once the screen is free")
        }
    }

    func testItemSpacingBlocksRepeatNudges() {
        var state = CoachState()
        let c = Fx.coach()
        Fx.use(Fx.reload, times: 3, from: 0, coach: c, state: &state)          // nudge at t=20
        XCTAssertEqual(Fx.use(Fx.reload, times: 3, from: 60, coach: c, state: &state), .record)
        // The nudge was at t=20, so 4 h after it is t=14420; t=14430 clears the spacing.
        guard case .nudge(let record) = c.handle(Fx.menu(Fx.reload, at: 4 * Fx.hour + 30), state: &state, context: Fx.ctx) else {
            return XCTFail("expected a nudge after the item spacing elapsed")
        }
        XCTAssertEqual(record.nudgeCount, 2)
    }

    func testGlobalSpacingBetweenDifferentItems() {
        var state = CoachState()
        let c = Fx.coach()
        Fx.use(Fx.reload, times: 3, from: 0, coach: c, state: &state)          // nudge at t=20
        XCTAssertEqual(Fx.use(Fx.printItem, times: 3, from: 30, coach: c, state: &state), .record) // t=50, 30 s after
        guard case .nudge = c.handle(Fx.menu(Fx.printItem, at: 20 + 90), state: &state, context: Fx.ctx) else {
            return XCTFail("expected a nudge once 90 s passed")
        }
    }

    func testDailyCapResetsAtMidnight() {
        var state = CoachState()
        let c = Fx.coach(CoachPolicy(nudgeAfter: 3, itemSpacing: 0, globalSpacing: 0, dailyCap: 2))
        guard case .nudge = Fx.use(Fx.reload, times: 3, from: 0, coach: c, state: &state) else { return XCTFail("1st nudge") }
        guard case .nudge = Fx.use(Fx.printItem, times: 3, from: 100, coach: c, state: &state) else { return XCTFail("2nd nudge") }
        XCTAssertEqual(Fx.use(Fx.paste, times: 3, from: 200, coach: c, state: &state), .record, "cap reached")
        XCTAssertEqual(state.nudgesByDay["2026-10-12"], 2)
        guard case .nudge = c.handle(Fx.menu(Fx.paste, at: Fx.day + 1), state: &state, context: Fx.ctx) else {
            return XCTFail("expected a nudge on the next day")
        }
        XCTAssertEqual(state.nudgesByDay["2026-10-13"], 1)
    }

    func testLearnedAfterThreeShortcutUsesThenRegression() {
        var state = CoachState()
        let c = Fx.coach()
        Fx.use(Fx.reload, times: 3, from: 0, coach: c, state: &state)          // coaching
        XCTAssertEqual(c.handle(Fx.key(Fx.reload, at: 100), state: &state, context: Fx.ctx), .record)
        XCTAssertEqual(c.handle(Fx.key(Fx.reload, at: 200), state: &state, context: Fx.ctx), .record)
        XCTAssertEqual(state.items[Fx.reload.identity]?.phase, .coaching)
        XCTAssertEqual(c.handle(Fx.key(Fx.reload, at: 300), state: &state, context: Fx.ctx), .record)
        XCTAssertEqual(state.items[Fx.reload.identity]?.phase, .learned)
        XCTAssertNotNil(state.items[Fx.reload.identity]?.learnedAt)

        // Three menu uses after learning stay quiet; the fifth regresses into gentle coaching.
        XCTAssertEqual(Fx.use(Fx.reload, times: 4, from: 5 * Fx.hour, coach: c, state: &state), .record)
        guard case .nudge(let record) = c.handle(Fx.menu(Fx.reload, at: 5 * Fx.hour + 100), state: &state, context: Fx.ctx) else {
            return XCTFail("expected a regression nudge on the fifth use")
        }
        XCTAssertEqual(record.phase, .coaching)
        XCTAssertEqual(record.regressions, 1)
        XCTAssertNil(record.learnedAt)
    }

    func testShortcutUsesBeforeCoachingDoNotLearn() {
        var state = CoachState()
        let c = Fx.coach()
        for i in 0..<5 {
            XCTAssertEqual(c.handle(Fx.key(Fx.reload, at: Double(i)), state: &state, context: Fx.ctx), .ignore)
        }
        XCTAssertNil(state.items[Fx.reload.identity], "ordinary shortcut traffic never creates a record")
        XCTAssertEqual(state, CoachState(), "and never touches the state file")
    }

    func testShortcutUsesAreCappedAtFifty() {
        var state = CoachState()
        let c = Fx.coach()
        Fx.use(Fx.reload, times: 3, from: 0, coach: c, state: &state) // coaching
        for i in 0..<60 {
            XCTAssertEqual(c.handle(Fx.key(Fx.reload, at: 100 + Double(i)), state: &state, context: Fx.ctx), .record)
            XCTAssertEqual(state.items[Fx.reload.identity]?.shortcutUses.count, min(i + 1, 50), "the cap trims exactly the overflow, use by use")
        }
        XCTAssertEqual(state.items[Fx.reload.identity]?.shortcutUses.count, 50, "only the latest 50 shortcut uses are kept")
        XCTAssertEqual(state.items[Fx.reload.identity]?.shortcutUses.first, Fx.base.addingTimeInterval(110), "the oldest ten are the ones dropped")
        XCTAssertEqual(state.items[Fx.reload.identity]?.shortcutUses.last, Fx.base.addingTimeInterval(159), "and the newest is kept")
        XCTAssertEqual(state.items[Fx.reload.identity]?.phase, .learned)
        XCTAssertEqual(state.log.filter { $0.kind == .shortcutUsed }.count, 60, "the log still records every use")
    }

    func testSnoozeBlocksUntilExpiry() {
        var state = CoachState()
        let c = Fx.coach()
        Fx.use(Fx.reload, times: 3, from: 0, coach: c, state: &state)          // nudge
        c.snooze(identity: Fx.reload.identity, until: Fx.base.addingTimeInterval(7 * Fx.day), state: &state)
        XCTAssertEqual(Fx.use(Fx.reload, times: 3, from: 5 * Fx.hour, coach: c, state: &state), .record)
        XCTAssertEqual(Fx.use(Fx.reload, times: 2, from: 8 * Fx.day, coach: c, state: &state), .record)
        guard case .nudge = c.handle(Fx.menu(Fx.reload, at: 8 * Fx.day + 30), state: &state, context: Fx.ctx) else {
            return XCTFail("expected a nudge after the snooze expired and three fresh uses")
        }
    }

    func testMuteAndUnmute() {
        var state = CoachState()
        let c = Fx.coach()
        Fx.use(Fx.reload, times: 3, from: 0, coach: c, state: &state)
        c.mute(identity: Fx.reload.identity, state: &state)
        XCTAssertEqual(Fx.use(Fx.reload, times: 6, from: 5 * Fx.hour, coach: c, state: &state), .record)
        XCTAssertEqual(state.items[Fx.reload.identity]?.phase, .muted)
        c.unmute(identity: Fx.reload.identity, state: &state)
        XCTAssertEqual(state.items[Fx.reload.identity]?.phase, .observed)
        XCTAssertEqual(state.items[Fx.reload.identity]?.menuUsesSinceLastNudge, 0)
    }

    func testDisabledItemIsIgnored() {
        var state = CoachState()
        var disabled = Fx.reload
        disabled.isEnabled = false
        XCTAssertEqual(Fx.coach().handle(Fx.menu(disabled, at: 0), state: &state, context: Fx.ctx), .ignore)
    }

    func testPruneRemovesStaleObservedItemsAndOldLog() {
        var state = CoachState()
        let c = Fx.coach()
        _ = c.handle(Fx.menu(Fx.reload, at: 0), state: &state, context: Fx.ctx)
        c.prune(state: &state, now: Fx.base.addingTimeInterval(8 * Fx.day))
        XCTAssertTrue(state.items.isEmpty, "a single week-old use leaves nothing to remember")
        XCTAssertEqual(state.log.count, 1, "the log keeps 30 days")
        c.prune(state: &state, now: Fx.base.addingTimeInterval(31 * Fx.day))
        XCTAssertTrue(state.log.isEmpty)
    }

    func testRekeyItemsAfterIdentityRuleChange() {
        var state = CoachState()
        var learned = ItemRecord(item: Fx.reload)
        learned.phase = .learned
        learned.shortcutUses = [Fx.base]
        state.items["com.apple.Safari|View›Reload Page (old rule)"] = learned
        var observed = ItemRecord(item: Fx.reload)
        observed.menuUses = [Fx.base, Fx.base, Fx.base]
        state.items[Fx.reload.identity] = observed
        state.rekeyItems()
        XCTAssertEqual(state.items.count, 1)
        XCTAssertEqual(state.items[Fx.reload.identity]?.phase, .learned, "the more advanced record wins the merge")

        var busier = ItemRecord(item: Fx.printItem)
        busier.menuUses = [Fx.base, Fx.base]
        busier.menuUsesSinceLastNudge = 2
        var quieter = ItemRecord(item: Fx.printItem)
        quieter.menuUses = [Fx.base]
        quieter.menuUsesSinceLastNudge = 1
        state.items["stale-a"] = quieter
        state.items["stale-b"] = busier
        state.rekeyItems()
        XCTAssertEqual(state.items[Fx.printItem.identity]?.menuUsesSinceLastNudge, 2, "same phase: busyness breaks the tie, whatever the key order")
        XCTAssertEqual(state.items[Fx.printItem.identity]?.menuUses.count, 3, "and the loser's uses are folded into the winner")
    }

    func testDayKeyUsesCalendarTimeZone() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(Coach(policy: .default, calendar: tokyo).dayKey(Fx.base.addingTimeInterval(20 * Fx.hour)), "2026-10-13")
        XCTAssertEqual(Fx.coach().dayKey(Fx.base.addingTimeInterval(20 * Fx.hour)), "2026-10-12")
    }
}

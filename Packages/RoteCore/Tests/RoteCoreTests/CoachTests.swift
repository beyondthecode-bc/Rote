import XCTest
@testable import RoteCore

final class CoachTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }()

    /// 2026-10-12 00:00:00 UTC, a Monday.
    private let base = Date(timeIntervalSince1970: 1_791_763_200)
    private let hour: TimeInterval = 3_600
    private let day: TimeInterval = 86_400

    private let reload = MenuItemRecord(bundleID: "com.apple.Safari", path: ["View", "Reload Page"], shortcut: Shortcut(modifiers: [.command], key: .character("R")))
    private let printItem = MenuItemRecord(bundleID: "com.apple.Safari", path: ["File", "Print…"], shortcut: Shortcut(modifiers: [.command], key: .character("P")))
    private let paste = MenuItemRecord(bundleID: "com.apple.Safari", path: ["Edit", "Paste"], shortcut: Shortcut(modifiers: [.command], key: .character("V")))

    private func coach(_ policy: CoachPolicy = .default) -> Coach { Coach(policy: policy, calendar: calendar) }
    private func menu(_ item: MenuItemRecord, at offset: TimeInterval) -> CoachEvent {
        CoachEvent(kind: .menuUsed, item: item, at: base.addingTimeInterval(offset))
    }
    private func key(_ item: MenuItemRecord, at offset: TimeInterval) -> CoachEvent {
        CoachEvent(kind: .shortcutUsed, item: item, at: base.addingTimeInterval(offset))
    }
    private let ctx = CoachContext()

    /// Drives `count` menu uses `step` seconds apart starting at `start`; returns the last decision.
    @discardableResult
    private func use(_ item: MenuItemRecord, times count: Int, from start: TimeInterval, step: TimeInterval = 10, coach c: Coach, state: inout CoachState, context: CoachContext? = nil) -> CoachDecision {
        var last: CoachDecision = .ignore
        for i in 0..<count {
            last = c.handle(menu(item, at: start + Double(i) * step), state: &state, context: context ?? ctx)
        }
        return last
    }

    func testThirdMenuUseNudges() {
        var state = CoachState()
        let c = coach()
        XCTAssertEqual(c.handle(menu(reload, at: 0), state: &state, context: ctx), .record)
        XCTAssertEqual(c.handle(menu(reload, at: 60), state: &state, context: ctx), .record)
        guard case .nudge(let record) = c.handle(menu(reload, at: 120), state: &state, context: ctx) else {
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
        var noShortcut = reload
        noShortcut.shortcut = nil
        XCTAssertEqual(coach().handle(menu(noShortcut, at: 0), state: &state, context: ctx), .ignore)
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertTrue(state.log.isEmpty)
    }

    func testOwnAppAndExcludedAppsAreIgnored() {
        var state = CoachState()
        let own = MenuItemRecord(bundleID: "com.beyondthecode.rote", path: ["Rote", "Quit"], shortcut: Shortcut(modifiers: [.command], key: .character("Q")))
        XCTAssertEqual(coach().handle(menu(own, at: 0), state: &state, context: ctx), .ignore)
        var excluded = ctx
        excluded.isAppExcluded = true
        XCTAssertEqual(coach().handle(menu(reload, at: 0), state: &state, context: excluded), .ignore)
        XCTAssertTrue(state.items.isEmpty)
    }

    func testPausedRecordsWithoutNudge() {
        var state = CoachState()
        var paused = ctx
        paused.isPaused = true
        XCTAssertEqual(use(reload, times: 3, from: 0, coach: coach(), state: &state, context: paused), .record)
        XCTAssertEqual(state.items[reload.identity]?.phase, .observed)
        XCTAssertEqual(state.items[reload.identity]?.menuUses.count, 3)
    }

    func testNudgeOnScreenOrOverlayBlocks() {
        var state = CoachState()
        var busy = ctx
        busy.isNudgeOnScreen = true
        XCTAssertEqual(use(reload, times: 3, from: 0, coach: coach(), state: &state, context: busy), .record)
        busy.isNudgeOnScreen = false
        busy.isOverlayVisible = true
        XCTAssertEqual(coach().handle(menu(reload, at: 100), state: &state, context: busy), .record)
        // The next free moment nudges: count since last nudge is already past the threshold.
        guard case .nudge = coach().handle(menu(reload, at: 200), state: &state, context: ctx) else {
            return XCTFail("expected a nudge once the screen is free")
        }
    }

    func testItemSpacingBlocksRepeatNudges() {
        var state = CoachState()
        let c = coach()
        use(reload, times: 3, from: 0, coach: c, state: &state)             // nudge at t=20
        XCTAssertEqual(use(reload, times: 3, from: 60, coach: c, state: &state), .record)
        // The nudge was at t=20, so 4 h after it is t=14420; t=14430 clears the spacing.
        guard case .nudge(let record) = c.handle(menu(reload, at: 4 * hour + 30), state: &state, context: ctx) else {
            return XCTFail("expected a nudge after the item spacing elapsed")
        }
        XCTAssertEqual(record.nudgeCount, 2)
    }

    func testGlobalSpacingBetweenDifferentItems() {
        var state = CoachState()
        let c = coach()
        use(reload, times: 3, from: 0, coach: c, state: &state)             // nudge at t=20
        XCTAssertEqual(use(printItem, times: 3, from: 30, coach: c, state: &state), .record) // t=50, 30 s after
        guard case .nudge = c.handle(menu(printItem, at: 20 + 90), state: &state, context: ctx) else {
            return XCTFail("expected a nudge once 90 s passed")
        }
    }

    func testDailyCapResetsAtMidnight() {
        var state = CoachState()
        let c = coach(CoachPolicy(nudgeAfter: 3, itemSpacing: 0, globalSpacing: 0, dailyCap: 2))
        guard case .nudge = use(reload, times: 3, from: 0, coach: c, state: &state) else { return XCTFail("1st nudge") }
        guard case .nudge = use(printItem, times: 3, from: 100, coach: c, state: &state) else { return XCTFail("2nd nudge") }
        XCTAssertEqual(use(paste, times: 3, from: 200, coach: c, state: &state), .record, "cap reached")
        XCTAssertEqual(state.nudgesByDay["2026-10-12"], 2)
        guard case .nudge = c.handle(menu(paste, at: day + 1), state: &state, context: ctx) else {
            return XCTFail("expected a nudge on the next day")
        }
        XCTAssertEqual(state.nudgesByDay["2026-10-13"], 1)
    }

    func testLearnedAfterThreeShortcutUsesThenRegression() {
        var state = CoachState()
        let c = coach()
        use(reload, times: 3, from: 0, coach: c, state: &state)             // coaching
        XCTAssertEqual(c.handle(key(reload, at: 100), state: &state, context: ctx), .record)
        XCTAssertEqual(c.handle(key(reload, at: 200), state: &state, context: ctx), .record)
        XCTAssertEqual(state.items[reload.identity]?.phase, .coaching)
        XCTAssertEqual(c.handle(key(reload, at: 300), state: &state, context: ctx), .record)
        XCTAssertEqual(state.items[reload.identity]?.phase, .learned)
        XCTAssertNotNil(state.items[reload.identity]?.learnedAt)

        // Three menu uses after learning stay quiet; the fifth regresses into gentle coaching.
        XCTAssertEqual(use(reload, times: 4, from: 5 * hour, coach: c, state: &state), .record)
        guard case .nudge(let record) = c.handle(menu(reload, at: 5 * hour + 100), state: &state, context: ctx) else {
            return XCTFail("expected a regression nudge on the fifth use")
        }
        XCTAssertEqual(record.phase, .coaching)
        XCTAssertEqual(record.regressions, 1)
        XCTAssertNil(record.learnedAt)
    }

    func testShortcutUsesBeforeCoachingDoNotLearn() {
        var state = CoachState()
        let c = coach()
        for i in 0..<5 { _ = c.handle(key(reload, at: Double(i)), state: &state, context: ctx) }
        XCTAssertEqual(state.items[reload.identity]?.phase, .observed)
    }

    func testSnoozeBlocksUntilExpiry() {
        var state = CoachState()
        let c = coach()
        use(reload, times: 3, from: 0, coach: c, state: &state)             // nudge
        c.snooze(identity: reload.identity, until: base.addingTimeInterval(7 * day), state: &state)
        XCTAssertEqual(use(reload, times: 3, from: 5 * hour, coach: c, state: &state), .record)
        XCTAssertEqual(use(reload, times: 2, from: 8 * day, coach: c, state: &state), .record)
        guard case .nudge = c.handle(menu(reload, at: 8 * day + 30), state: &state, context: ctx) else {
            return XCTFail("expected a nudge after the snooze expired and three fresh uses")
        }
    }

    func testMuteAndUnmute() {
        var state = CoachState()
        let c = coach()
        use(reload, times: 3, from: 0, coach: c, state: &state)
        c.mute(identity: reload.identity, state: &state)
        XCTAssertEqual(use(reload, times: 6, from: 5 * hour, coach: c, state: &state), .record)
        XCTAssertEqual(state.items[reload.identity]?.phase, .muted)
        c.unmute(identity: reload.identity, state: &state)
        XCTAssertEqual(state.items[reload.identity]?.phase, .observed)
        XCTAssertEqual(state.items[reload.identity]?.menuUsesSinceLastNudge, 0)
    }

    func testDisabledItemIsIgnored() {
        var state = CoachState()
        var disabled = reload
        disabled.isEnabled = false
        XCTAssertEqual(coach().handle(menu(disabled, at: 0), state: &state, context: ctx), .ignore)
    }

    func testPruneRemovesStaleObservedItemsAndOldLog() {
        var state = CoachState()
        let c = coach()
        _ = c.handle(menu(reload, at: 0), state: &state, context: ctx)
        c.prune(state: &state, now: base.addingTimeInterval(8 * day))
        XCTAssertTrue(state.items.isEmpty, "a single week-old use leaves nothing to remember")
        XCTAssertEqual(state.log.count, 1, "the log keeps 30 days")
        c.prune(state: &state, now: base.addingTimeInterval(31 * day))
        XCTAssertTrue(state.log.isEmpty)
    }

    func testRekeyItemsAfterIdentityRuleChange() {
        var state = CoachState()
        var learned = ItemRecord(item: reload)
        learned.phase = .learned
        learned.shortcutUses = [base]
        state.items["com.apple.Safari|View›Reload Page (old rule)"] = learned
        var observed = ItemRecord(item: reload)
        observed.menuUses = [base, base, base]
        state.items[reload.identity] = observed
        state.rekeyItems()
        XCTAssertEqual(state.items.count, 1)
        XCTAssertEqual(state.items[reload.identity]?.phase, .learned, "the more advanced record wins the merge")

        var busier = ItemRecord(item: printItem)
        busier.menuUses = [base, base]
        var quieter = ItemRecord(item: printItem)
        quieter.menuUses = [base]
        state.items["stale-a"] = busier
        state.items["stale-b"] = quieter
        state.rekeyItems()
        XCTAssertEqual(state.items[printItem.identity]?.menuUses.count, 2, "same phase: busyness breaks the tie")
    }

    func testDayKeyUsesCalendarTimeZone() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(Coach(policy: .default, calendar: tokyo).dayKey(base.addingTimeInterval(20 * hour)), "2026-10-13")
        XCTAssertEqual(coach().dayKey(base.addingTimeInterval(20 * hour)), "2026-10-12")
    }
}

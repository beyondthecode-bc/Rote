import XCTest
@testable import RoteCore

/// Rule and boundary tests for the coach (spec §6.2) that the walk-through cases in `CoachTests`
/// leave open: the exact edge of every gate, what a suppressed nudge does and does not consume,
/// the learned/regressed transitions, housekeeping, persistence and purity.
/// Rule numbers refer to spec §6.2; the expectations come from the spec, not from the code.
final class CoachRulesTests: XCTestCase {
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
    private let ctx = CoachContext()

    private func coach(_ policy: CoachPolicy = .default) -> Coach { Coach(policy: policy, calendar: calendar) }
    private func menu(_ item: MenuItemRecord, at offset: TimeInterval) -> CoachEvent {
        CoachEvent(kind: .menuUsed, item: item, at: base.addingTimeInterval(offset))
    }
    private func key(_ item: MenuItemRecord, at offset: TimeInterval) -> CoachEvent {
        CoachEvent(kind: .shortcutUsed, item: item, at: base.addingTimeInterval(offset))
    }
    /// Distinct items for multi-item scenarios: same menu, different title.
    private func item(_ title: String, _ key: String = "R", bundle: String = "com.apple.Safari") -> MenuItemRecord {
        MenuItemRecord(bundleID: bundle, path: ["View", title], shortcut: Shortcut(modifiers: [.command], key: .character(key)))
    }
    private func isNudge(_ decision: CoachDecision) -> Bool {
        if case .nudge = decision { return true } else { return false }
    }

    /// Coaching, then learned: three menu uses (the first nudge lands at t=2), three shortcut uses.
    private func learnedState(_ c: Coach, _ a: MenuItemRecord) -> CoachState {
        var s = CoachState()
        for i in 0..<3 { _ = c.handle(menu(a, at: Double(i)), state: &s, context: ctx) }
        for i in 0..<3 { _ = c.handle(key(a, at: 100 + Double(i)), state: &s, context: ctx) }
        return s
    }

    /// Coaching, learned, then regressed: five menu uses after learning nudge again; `regressions == 1`.
    private func regressedState(_ c: Coach, _ a: MenuItemRecord) -> CoachState {
        var s = learnedState(c, a)
        for i in 0..<5 { _ = c.handle(menu(a, at: 6 * hour + Double(i)), state: &s, context: ctx) }
        XCTAssertEqual(s.items[a.identity]?.phase, .coaching)
        XCTAssertEqual(s.items[a.identity]?.regressions, 1)
        return s
    }

    // MARK: - Rules 6-9: a suppressed nudge is dropped, never queued, and never consumes the count

    func testRule9NudgeOnScreenOrOverlaySuppressesWithoutConsumingTheCount() {
        for variant in ["isNudgeOnScreen", "isOverlayVisible"] {
            var s = CoachState()
            let c = coach()
            let a = item("A", "A")
            var busy = ctx
            if variant == "isNudgeOnScreen" { busy.isNudgeOnScreen = true } else { busy.isOverlayVisible = true }
            for i in 0..<5 {
                XCTAssertEqual(c.handle(menu(a, at: Double(i) * 10), state: &s, context: busy), .record, variant)
            }
            let r = s.items[a.identity]!
            XCTAssertEqual(r.menuUsesSinceLastNudge, 5, variant)
            XCTAssertEqual(r.phase, .observed, variant)
            XCTAssertNil(r.lastNudgeAt, variant)
            XCTAssertEqual(r.nudgeCount, 0, variant)
            XCTAssertNil(s.lastNudgeAt, variant)
            XCTAssertTrue(s.nudgesByDay.isEmpty, variant)
            guard case .nudge(let n) = c.handle(menu(a, at: 100), state: &s, context: ctx) else {
                return XCTFail("next free moment must nudge: \(variant)")
            }
            XCTAssertEqual(n.nudgeCount, 1, variant)
        }
    }

    func testRule8DailyCapSuppressesWithoutConsumingTheCountThenNextDayNudges() {
        var s = CoachState()
        let c = coach(CoachPolicy(nudgeAfter: 3, itemSpacing: 0, globalSpacing: 0, dailyCap: 1))
        let a = item("A", "A")
        let b = item("B", "B")
        for i in 0..<3 { _ = c.handle(menu(a, at: Double(i)), state: &s, context: ctx) }
        XCTAssertEqual(s.nudgesByDay["2026-10-12"], 1)
        let lastBefore = s.lastNudgeAt
        for i in 0..<4 {
            XCTAssertEqual(c.handle(menu(b, at: 100 + Double(i)), state: &s, context: ctx), .record)
        }
        XCTAssertEqual(s.items[b.identity]?.menuUsesSinceLastNudge, 4, "cap-suppressed uses stay counted")
        XCTAssertEqual(s.nudgesByDay["2026-10-12"], 1, "suppressed events must not bump the day counter")
        XCTAssertEqual(s.lastNudgeAt, lastBefore, "suppressed events must not move the global nudge clock")
        XCTAssertTrue(isNudge(c.handle(menu(b, at: day + 1), state: &s, context: ctx)), "first use of the next day nudges")
    }

    func testRule7GlobalSpacingSuppressesWithoutConsumingTheCountAndAllowsExactlyAtTheSpacing() {
        var s = CoachState()
        let c = coach(CoachPolicy(nudgeAfter: 3, itemSpacing: 0, globalSpacing: 90, dailyCap: 100))
        let a = item("A", "A")
        let b = item("B", "B")
        for i in 0..<3 { _ = c.handle(menu(a, at: Double(i)), state: &s, context: ctx) } // nudge at t=2
        for i in 0..<3 {
            XCTAssertEqual(c.handle(menu(b, at: 10 + Double(i)), state: &s, context: ctx), .record)
        }
        XCTAssertEqual(s.items[b.identity]?.menuUsesSinceLastNudge, 3)
        XCTAssertTrue(isNudge(c.handle(menu(b, at: 2 + 90), state: &s, context: ctx)), "exactly globalSpacing after: allowed (at least)")
    }

    func testRule6ItemSpacingSuppressesWithoutConsumingTheCountAndAllowsExactlyAtTheSpacing() {
        var s = CoachState()
        let c = coach()
        let a = item("A", "A")
        for i in 0..<3 { _ = c.handle(menu(a, at: Double(i)), state: &s, context: ctx) } // nudge at t=2
        for i in 0..<5 {
            XCTAssertEqual(c.handle(menu(a, at: 100 + Double(i)), state: &s, context: ctx), .record)
        }
        XCTAssertEqual(s.items[a.identity]?.menuUsesSinceLastNudge, 5)
        XCTAssertTrue(isNudge(c.handle(menu(a, at: 2 + 4 * hour), state: &s, context: ctx)), "exactly itemSpacing after: allowed (at least)")
    }

    // MARK: - Boundaries just inside the limits

    func testRules6And7StillBlockHalfASecondBeforeTheSpacingElapses() {
        var s = CoachState()
        let c = coach()
        let a = item("A", "A")
        let b = item("B", "B")
        for i in 0..<3 { _ = c.handle(menu(a, at: Double(i)), state: &s, context: ctx) } // nudge at t=2
        for i in 0..<2 { _ = c.handle(menu(a, at: 100 + Double(i)), state: &s, context: ctx) }
        XCTAssertEqual(c.handle(menu(a, at: 2 + 4 * hour - 0.5), state: &s, context: ctx), .record, "0.5 s short of itemSpacing")
        for i in 0..<2 { _ = c.handle(menu(b, at: 10 + Double(i)), state: &s, context: ctx) }
        XCTAssertEqual(c.handle(menu(b, at: 2 + 89.5), state: &s, context: ctx), .record, "0.5 s short of globalSpacing")
    }

    func testRule8DailyCapAllowsExactlyCapNudgesAndBlocksTheNext() {
        var s = CoachState()
        let c = coach(CoachPolicy(nudgeAfter: 3, itemSpacing: 0, globalSpacing: 0, dailyCap: 3))
        for (n, letter) in ["A", "B", "C", "D"].enumerated() {
            let it = item(letter, letter)
            var last: CoachDecision = .ignore
            for i in 0..<3 {
                last = c.handle(menu(it, at: Double(n) * 100 + Double(i)), state: &s, context: ctx)
            }
            if n < 3 {
                XCTAssertTrue(isNudge(last), "nudge #\(n + 1) of cap 3 must be shown")
            } else {
                XCTAssertEqual(last, .record, "4th is capped")
            }
        }
        XCTAssertEqual(s.nudgesByDay["2026-10-12"], 3)
    }

    // MARK: - Learned items and regression

    func testRule4LearnedItemStaysQuietUntilRegressAfterUses() {
        let c = coach()
        let a = item("A", "A")
        var s = learnedState(c, a)
        XCTAssertEqual(s.items[a.identity]?.phase, .learned)
        for i in 0..<4 {
            XCTAssertEqual(c.handle(menu(a, at: 5 * hour + Double(i)), state: &s, context: ctx), .record)
        }
        XCTAssertEqual(s.items[a.identity]?.phase, .learned, "spec rule 4: learned items are not nudged")
    }

    func testRegressionSuppressedByRule9WaitsForAFreeMoment() {
        let c = coach()
        let a = item("A", "A")
        var s = learnedState(c, a)
        var overlay = ctx
        overlay.isOverlayVisible = true
        for i in 0..<6 { _ = c.handle(menu(a, at: 5 * hour + Double(i)), state: &s, context: overlay) }
        guard case .nudge(let r) = c.handle(menu(a, at: 5 * hour + 100), state: &s, context: ctx) else {
            return XCTFail("free moment must regress+nudge")
        }
        XCTAssertEqual(r.phase, .coaching)
        XCTAssertEqual(r.regressions, 1)
    }

    func testRule5MenuUsesBeforeLearningDoNotCountTowardRegression() {
        let c = coach()
        let a = item("A", "A")
        var s = CoachState()
        for i in 0..<3 { _ = c.handle(menu(a, at: Double(i)), state: &s, context: ctx) }      // nudge #1
        for i in 0..<2 { _ = c.handle(menu(a, at: 50 + Double(i)), state: &s, context: ctx) } // 2 menu uses while coaching (blocked by spacing)
        for i in 0..<3 { _ = c.handle(key(a, at: 100 + Double(i)), state: &s, context: ctx) } // learned
        XCTAssertEqual(s.items[a.identity]?.phase, .learned)
        XCTAssertEqual(s.items[a.identity]?.menuUsesSinceLastNudge, 0)
        for i in 0..<4 {
            XCTAssertEqual(c.handle(menu(a, at: 6 * hour + Double(i)), state: &s, context: ctx), .record)
        }
        XCTAssertTrue(isNudge(c.handle(menu(a, at: 6 * hour + 10), state: &s, context: ctx)), "fifth use after learning regresses")
    }

    func testRule5GentleCadenceAfterRegressionNeedsFiveUsesNotThree() {
        let c = coach()
        let a = item("A", "A")
        var s = learnedState(c, a)
        for i in 0..<5 { _ = c.handle(menu(a, at: 6 * hour + Double(i)), state: &s, context: ctx) } // regress nudge at 5th
        XCTAssertEqual(s.items[a.identity]?.regressions, 1)
        let t0 = 12 * hour
        XCTAssertEqual(c.handle(menu(a, at: t0), state: &s, context: ctx), .record)
        XCTAssertEqual(c.handle(menu(a, at: t0 + 1), state: &s, context: ctx), .record)
        XCTAssertEqual(c.handle(menu(a, at: t0 + 2), state: &s, context: ctx), .record, "3rd use: nudgeAfter would fire, gentle cadence must not")
        XCTAssertEqual(c.handle(menu(a, at: t0 + 3), state: &s, context: ctx), .record)
        XCTAssertTrue(isNudge(c.handle(menu(a, at: t0 + 4), state: &s, context: ctx)), "5th use fires")
    }

    func testRelearningAfterRegressionNeedsLearnAfterNewShortcutUses() {
        let c = coach()
        let a = item("A", "A")
        var s = regressedState(c, a)
        XCTAssertEqual(s.items[a.identity]?.shortcutUsesSinceCoaching, 0, "regression restarts the shortcut count")
        _ = c.handle(key(a, at: 7 * hour), state: &s, context: ctx)
        _ = c.handle(key(a, at: 7 * hour + 1), state: &s, context: ctx)
        XCTAssertEqual(s.items[a.identity]?.phase, .coaching, "2 new shortcut uses: not learned yet")
        _ = c.handle(key(a, at: 7 * hour + 2), state: &s, context: ctx)
        XCTAssertEqual(s.items[a.identity]?.phase, .learned, "3rd new shortcut use: learned again")
        XCTAssertNotNil(s.items[a.identity]?.learnedAt)
    }

    // MARK: - Pause, snooze, mute

    func testMutedItemStillCountsShortcutUsesAndKeepsItsPhase() {
        let c = coach()
        var s = CoachState()
        let b = item("B", "B")
        for i in 0..<3 { _ = c.handle(menu(b, at: 200 + Double(i)), state: &s, context: ctx) }
        c.mute(identity: b.identity, state: &s)
        for i in 0..<5 { _ = c.handle(key(b, at: 300 + Double(i)), state: &s, context: ctx) }
        XCTAssertEqual(s.items[b.identity]?.phase, .muted, "muted never changes phase on shortcut use")
        XCTAssertEqual(s.items[b.identity]?.shortcutUses.count, 5, "muted: still counted")
    }

    func testUnmuteClearsSnoozeNudgeClockAndCounters() {
        let c = coach()
        let a = item("A", "A")
        var s = CoachState()
        for i in 0..<3 { _ = c.handle(menu(a, at: Double(i)), state: &s, context: ctx) } // nudge at t=2
        c.snooze(identity: a.identity, until: base.addingTimeInterval(7 * day), state: &s)
        c.mute(identity: a.identity, state: &s)
        c.unmute(identity: a.identity, state: &s)
        let r = s.items[a.identity]!
        XCTAssertNil(r.snoozedUntil)
        XCTAssertNil(r.lastNudgeAt)
        XCTAssertEqual(r.phase, .observed)
        XCTAssertEqual(r.menuUsesSinceLastNudge, 0)
        XCTAssertEqual(r.shortcutUsesSinceCoaching, 0)
        // fresh start: needs nudgeAfter new uses, then the item-spacing is no longer a barrier
        for i in 0..<2 {
            XCTAssertEqual(c.handle(menu(a, at: 100 + Double(i)), state: &s, context: ctx), .record)
        }
        XCTAssertTrue(isNudge(c.handle(menu(a, at: 102), state: &s, context: ctx)), "3rd fresh use, 100 s after the global nudge at t=2: nudges (item spacing was reset by unmute)")
    }

    func testUserActionsOnAnUnknownIdentityAreSilentNoOps() {
        let c = coach()
        var empty = CoachState()
        c.mute(identity: "nope", state: &empty)
        c.snooze(identity: "nope", until: base, state: &empty)
        c.unmute(identity: "nope", state: &empty)
        c.clearSnooze(identity: "nope", state: &empty)
        XCTAssertTrue(empty.items.isEmpty, "actions on an unknown identity are silent no-ops")
    }

    func testRule1PerAppPauseRecordsWithoutConsumingTheCountThenResumes() {
        let c = coach()
        let a = item("A", "A")
        var s = CoachState()
        var appPaused = ctx
        appPaused.isAppPaused = true
        for i in 0..<6 {
            XCTAssertEqual(c.handle(menu(a, at: Double(i)), state: &s, context: appPaused), .record)
        }
        XCTAssertEqual(s.items[a.identity]?.menuUses.count, 6)
        XCTAssertEqual(s.items[a.identity]?.phase, .observed)
        XCTAssertTrue(isNudge(c.handle(menu(a, at: 10), state: &s, context: ctx)), "first use after resuming nudges (count was never consumed)")
    }

    func testSnoozeEndsExactlyAtTheUntilInstant() {
        let c = coach()
        let a = item("A", "A")
        var s = CoachState()
        for i in 0..<3 { _ = c.handle(menu(a, at: Double(i)), state: &s, context: ctx) } // nudge at t=2
        let until = 5 * hour
        c.snooze(identity: a.identity, until: base.addingTimeInterval(until), state: &s)
        for i in 0..<3 { _ = c.handle(menu(a, at: 4 * hour + Double(i)), state: &s, context: ctx) } // 3 uses, snoozed, 4h > spacing
        XCTAssertEqual(c.handle(menu(a, at: until - 1), state: &s, context: ctx), .record, "1 s before until: snoozed")
        XCTAssertTrue(isNudge(c.handle(menu(a, at: until), state: &s, context: ctx)), "at until: snooze over (spec: hidden 'until until')")
    }

    // MARK: - Rule 3: items without a usable shortcut never touch state

    func testRule3ItemsWithoutAUsableShortcutNeverTouchState() {
        let c = coach()
        var s = CoachState()
        let none = MenuItemRecord(bundleID: "com.apple.Safari", path: ["File", "Open"], shortcut: nil)
        let weird = MenuItemRecord(bundleID: "com.apple.Safari", path: ["File", "Weird"], shortcut: nil, hasUnrenderableShortcut: true)
        for it in [none, weird] {
            for k in [CoachEvent.Kind.menuUsed, .shortcutUsed] {
                XCTAssertEqual(c.handle(CoachEvent(kind: k, item: it, at: base), state: &s, context: ctx), .ignore)
            }
        }
        XCTAssertEqual(s, CoachState())
    }

    // MARK: - Housekeeping

    func testPruneKeepsMutedLearnedCoachingAndActivelySnoozedItemsAndDropsEmptyObserved() {
        let c = coach()
        var s = CoachState()
        let far = base.addingTimeInterval(200 * day)
        let cases: [(String, ItemPhase, Date?)] = [
            ("muted", .muted, nil),
            ("learned", .learned, nil),
            ("coaching", .coaching, nil),
            ("observedSnoozed", .observed, far),
            ("observedExpiredSnooze", .observed, base.addingTimeInterval(day)),
            ("observedEmpty", .observed, nil)
        ]
        for (name, phase, snooze) in cases {
            var r = ItemRecord(item: item(name, name))
            r.phase = phase
            r.snoozedUntil = snooze
            s.items[r.identity] = r
        }
        c.prune(state: &s, now: base.addingTimeInterval(100 * day))
        let kept = Set(s.items.values.map { $0.item.title })
        XCTAssertTrue(kept.contains("muted"))
        XCTAssertTrue(kept.contains("learned"))
        XCTAssertTrue(kept.contains("coaching"))
        XCTAssertTrue(kept.contains("observedSnoozed"), "an active snooze must survive prune")
        XCTAssertFalse(kept.contains("observedExpiredSnooze"))
        XCTAssertFalse(kept.contains("observedEmpty"))
    }

    func testPruneKeepsLogAndDayCountersExactlyAtTheRetentionCutoff() {
        let c = coach()
        var s = CoachState()
        let now = base.addingTimeInterval(60 * day)
        let cutoff = now.addingTimeInterval(-30 * day)
        let a = item("A", "A")
        s.log = [
            LogEntry(at: cutoff.addingTimeInterval(-1), kind: .menuUsed, identity: a.identity, bundleID: a.bundleID, hadShortcut: true, phaseAfter: .observed),
            LogEntry(at: cutoff, kind: .menuUsed, identity: a.identity, bundleID: a.bundleID, hadShortcut: true, phaseAfter: .observed)
        ]
        let cutoffKey = c.dayKey(cutoff)
        s.nudgesByDay = ["2000-01-01": 5, cutoffKey: 2, c.dayKey(now): 1]
        c.prune(state: &s, now: now)
        XCTAssertEqual(s.log.count, 1, "entry exactly at the cutoff is kept, 1 s older is dropped")
        XCTAssertEqual(Set(s.nudgesByDay.keys), [cutoffKey, c.dayKey(now)])
    }

    // MARK: - Day keys and the local calendar day

    func testDayKeyIsSortableGregorianInManyTimeZones() {
        for zone in ["UTC", "America/New_York", "Europe/London", "Pacific/Apia", "Pacific/Kiritimati", "Asia/Kolkata", "Australia/Lord_Howe"] {
            var g = Calendar(identifier: .gregorian)
            g.timeZone = TimeZone(identifier: zone)!
            let c = Coach(policy: .default, calendar: g)
            var prevKey = ""
            var prevStart = Date.distantPast
            var t = base.addingTimeInterval(-800 * day)
            var checked = 0
            while t < base.addingTimeInterval(800 * day) {
                let key = c.dayKey(t)
                let start = g.startOfDay(for: t)
                if !prevKey.isEmpty {
                    XCTAssertTrue(key >= prevKey, "\(zone): key went backwards \(prevKey) -> \(key)")
                    XCTAssertEqual(key > prevKey, start > prevStart, "\(zone): key order must equal local-day order at \(t)")
                }
                prevKey = key
                prevStart = start
                t = t.addingTimeInterval(37 * 60)
                checked += 1
            }
            XCTAssertGreaterThan(checked, 1000)
        }
        // year 1000..9999 stay 4 wide
        XCTAssertEqual(coach().dayKey(Date(timeIntervalSince1970: -30_000_000_000)).count, 10)
    }

    func testRule8DailyCapFollowsTheInjectedCalendarsTimeZone() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let c = Coach(policy: CoachPolicy(nudgeAfter: 3, itemSpacing: 0, globalSpacing: 0, dailyCap: 1), calendar: tokyo)
        var s = CoachState()
        let a = item("A", "A")
        let b = item("B", "B")
        // base = 00:00 UTC = 09:00 JST on 2026-10-12; 14:59 UTC = 23:59 JST same day; 15:00 UTC = next JST day
        for i in 0..<3 { _ = c.handle(menu(a, at: 14 * hour + 59 * 60 + Double(i)), state: &s, context: ctx) }
        XCTAssertEqual(s.nudgesByDay["2026-10-12"], 1)
        for i in 0..<3 {
            XCTAssertEqual(c.handle(menu(b, at: 14 * hour + 59 * 60 + 10 + Double(i)), state: &s, context: ctx), .record, "same JST day: capped")
        }
        XCTAssertTrue(isNudge(c.handle(menu(b, at: 15 * hour + 1), state: &s, context: ctx)), "JST midnight passed: new day")
        XCTAssertEqual(s.nudgesByDay["2026-10-13"], 1)
    }

    // MARK: - Differential: the dual counters against a direct model of rules 5 and 6

    private struct XorShift {
        var s: UInt64
        mutating func next() -> UInt64 {
            s ^= s >> 12
            s ^= s << 25
            s ^= s >> 27
            return s &* 2685821657736338717
        }
    }

    func testNudgeCadenceMatchesADirectModelOfRules5And6() {
        let steps: [TimeInterval] = [1, 30, 60, 3_600, 4 * 3_600 - 1, 4 * 3_600, 4 * 3_600 + 1, 86_400, 3 * 86_400, 7 * 86_400 - 1, 7 * 86_400, 7 * 86_400 + 1, 8 * 86_400, 20 * 86_400]
        var rng = XorShift(s: 0x9E3779B97F4A7C15)
        var mismatches = 0
        var nudgesSeen = 0
        for trial in 0..<400 {
            let spacing: TimeInterval = trial % 2 == 0 ? 0 : 4 * 3_600
            let T = 2 + trial % 4 // 2...5 (the Settings range for nudgeAfter)
            let policy = CoachPolicy(nudgeAfter: T, itemSpacing: spacing, globalSpacing: 0, dailyCap: 10_000)
            let c = coach(policy)
            var s = CoachState()
            let a = item("A", "A")
            var sinceReset: [TimeInterval] = []
            var lastNudge: TimeInterval? = nil
            var t: TimeInterval = 0
            for _ in 0..<80 {
                t += steps[Int(rng.next() % UInt64(steps.count))]
                // reference (spec rule 5 + rule 6, read literally)
                sinceReset.append(t)
                let inWindow = sinceReset.filter { $0 >= t - policy.window }.count
                var expectNudge = inWindow >= T
                if expectNudge, let l = lastNudge, t - l < spacing { expectNudge = false }
                if expectNudge {
                    sinceReset = []
                    lastNudge = t
                }
                let got = isNudge(c.handle(menu(a, at: t), state: &s, context: ctx))
                if got { nudgesSeen += 1 }
                if got != expectNudge { mismatches += 1 }
            }
        }
        XCTAssertEqual(mismatches, 0)
        XCTAssertGreaterThan(nudgesSeen, 500)
    }

    // MARK: - Rekey, identity merging, persistence and purity

    func testRekeyPrefersMutedThenLearnedThenCoachingThenObservedRegardlessOfBusyness() {
        let phases: [ItemPhase] = [.muted, .learned, .coaching, .observed]
        for (i, hi) in phases.enumerated() {
            for lo in phases[(i + 1)...] {
                var s = CoachState()
                var a = ItemRecord(item: item("A", "A"))
                a.phase = hi
                var b = ItemRecord(item: item("A", "A"))
                b.phase = lo
                b.menuUses = Array(repeating: base, count: 50) // far busier, must still lose
                s.items["k1"] = b
                s.items["k2"] = a
                s.rekeyItems()
                XCTAssertEqual(s.items.count, 1)
                XCTAssertEqual(s.items.values.first?.phase, hi, "\(hi) must beat busier \(lo)")
            }
        }
    }

    func testDynamicTitlesShareOneRecordAndKeepTheLatestTitle() {
        let c = coach()
        var s = CoachState()
        let t1 = MenuItemRecord(bundleID: "com.apple.Safari", path: ["File", "Close Tab “Alpha”"], shortcut: Shortcut(modifiers: [.command], key: .character("W")))
        let t2 = MenuItemRecord(bundleID: "com.apple.Safari", path: ["File", "Close Tab “Beta”"], shortcut: Shortcut(modifiers: [.command], key: .character("W")))
        _ = c.handle(menu(t1, at: 0), state: &s, context: ctx)
        _ = c.handle(menu(t2, at: 1), state: &s, context: ctx)
        XCTAssertEqual(s.items.count, 1)
        XCTAssertEqual(s.items.values.first?.item.title, "Close Tab “Beta”")
        XCTAssertEqual(s.items.values.first?.menuUses.count, 2)
    }

    func testStateRoundTripsThroughCodableWithEveryDateStrategy() throws {
        let c = coach()
        var s = CoachState()
        let a = item("A", "A")
        let b = item("B", "B")
        for i in 0..<3 { _ = c.handle(menu(a, at: Double(i)), state: &s, context: ctx) }
        _ = c.handle(key(a, at: 50), state: &s, context: ctx)
        c.snooze(identity: a.identity, until: base.addingTimeInterval(7 * day), state: &s)
        _ = c.handle(menu(b, at: 60), state: &s, context: ctx)
        c.mute(identity: b.identity, state: &s)
        for strategy in [JSONEncoder.DateEncodingStrategy.deferredToDate, .iso8601, .secondsSince1970] {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = strategy
            let dec = JSONDecoder()
            switch strategy {
            case .iso8601: dec.dateDecodingStrategy = .iso8601
            case .secondsSince1970: dec.dateDecodingStrategy = .secondsSince1970
            default: break
            }
            let data = try enc.encode(s)
            let back = try dec.decode(CoachState.self, from: data)
            if case .iso8601 = strategy {
                XCTAssertEqual(back.items.count, s.items.count)
            } else {
                XCTAssertEqual(back, s)
            }
            XCTAssertEqual(back.schemaVersion, 1)
        }
    }

    func testSameEventsGiveSameDecisions() {
        func run() -> [String] {
            let c = coach()
            var s = CoachState()
            var out: [String] = []
            let a = item("A", "A")
            let b = item("B", "B")
            for k in 0..<40 {
                let it = k % 3 == 0 ? b : a
                let ev = k % 5 == 4 ? key(it, at: Double(k) * 77) : menu(it, at: Double(k) * 77)
                out.append("\(c.handle(ev, state: &s, context: ctx))")
            }
            return out
        }
        XCTAssertEqual(run(), run())
    }

    // MARK: - Hardening: deterministic rekey, clamped policy, Gregorian day keys, unmute

    func testRekeyIsDeterministicOnExactTies() {
        for _ in 0..<20 {
            var state = CoachState()
            var first = ItemRecord(item: reload)
            first.nudgeCount = 1
            var second = ItemRecord(item: reload)
            second.nudgeCount = 2
            state.items["a-stale"] = first
            state.items["z-stale"] = second
            state.rekeyItems()
            XCTAssertEqual(state.items.count, 1)
            XCTAssertEqual(state.items[reload.identity]?.nudgeCount, 1, "exact ties keep the first record by key order")
        }
    }

    func testPolicyClampsNonsense() {
        let policy = CoachPolicy(nudgeAfter: 0, window: -5, itemSpacing: -1, globalSpacing: -1, dailyCap: -3, learnAfter: 0, regressAfter: 0, logRetention: 0)
        XCTAssertEqual(policy.nudgeAfter, 1)
        XCTAssertEqual(policy.window, 60)
        XCTAssertEqual(policy.itemSpacing, 0)
        XCTAssertEqual(policy.globalSpacing, 0)
        XCTAssertEqual(policy.dailyCap, 0)
        XCTAssertEqual(policy.learnAfter, 1)
        XCTAssertEqual(policy.regressAfter, 1)
        XCTAssertEqual(policy.logRetention, 86_400)
    }

    func testDayKeyIsGregorianWhateverTheCalendar() {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(Coach(policy: .default, calendar: japanese).dayKey(base), "2026-10-12")
    }

    func testUnmuteClearsLearnedAt() {
        var state = CoachState()
        var record = ItemRecord(item: reload)
        record.phase = .learned
        record.learnedAt = base
        state.items[reload.identity] = record
        let c = coach()
        c.mute(identity: reload.identity, state: &state)
        c.unmute(identity: reload.identity, state: &state)
        XCTAssertNil(state.items[reload.identity]?.learnedAt)
        XCTAssertEqual(state.items[reload.identity]?.phase, .observed)
    }
}

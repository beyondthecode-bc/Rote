import XCTest
@testable import RoteCore

final class StatsTests: XCTestCase {
    private func calendar(firstWeekday: Int) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = firstWeekday
        return c
    }

    /// Monday-first weeks in New York, which leaves daylight time on Sunday 2026-11-01
    /// and enters it on Sunday 2027-03-14.
    private func newYork() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.firstWeekday = 2
        return c
    }

    /// Sunday 2026-10-18 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_792_324_800)
    private let day: TimeInterval = 86_400
    private let hour: TimeInterval = 3_600

    private let reload = MenuItemRecord(bundleID: "com.apple.Safari", path: ["View", "Reload Page"], shortcut: Shortcut(modifiers: [.command], key: .character("R")))
    private let build = MenuItemRecord(bundleID: "com.apple.dt.Xcode", path: ["Product", "Build"], shortcut: Shortcut(modifiers: [.command], key: .character("B")))
    private let newTab = MenuItemRecord(bundleID: "com.apple.Safari", path: ["File", "New Tab"], shortcut: Shortcut(modifiers: [.command], key: .character("T")))
    private let newFolder = MenuItemRecord(bundleID: "com.apple.finder", path: ["File", "New Folder"], shortcut: Shortcut(modifiers: [.shift, .command], key: .character("N")))
    private let closeTab = MenuItemRecord(bundleID: "com.apple.Safari", path: ["File", "Close Tab"], shortcut: Shortcut(modifiers: [.command], key: .character("W")))
    private let find = MenuItemRecord(bundleID: "com.apple.Safari", path: ["Edit", "Find…"], shortcut: Shortcut(modifiers: [.command], key: .character("F")))

    private func item(_ title: String, bundle: String = "com.apple.Safari", menu: String = "File") -> MenuItemRecord {
        MenuItemRecord(bundleID: bundle, path: [menu, title], shortcut: Shortcut(modifiers: [.command], key: .character("K")))
    }

    private func entry(_ at: Date, _ kind: CoachEvent.Kind, _ phase: ItemPhase, _ item: MenuItemRecord? = nil) -> LogEntry {
        let item = item ?? reload
        return LogEntry(at: at, kind: kind, identity: item.identity, bundleID: item.bundleID, phaseAfter: phase)
    }

    /// A log the coach could have written, oldest first. With Monday-first weeks, Reload Page
    /// and New Tab are learned last week and New Folder this week (Tuesday Oct 13); Build is
    /// being coached. Find… was learned and Close Tab muted before the log begins. Uses of a
    /// learned item (New Tab, Find…) count without being a learning; muted menu uses count.
    private func state() -> CoachState {
        var s = CoachState()
        for (item, learnedAt) in [(reload, now - 12 * day), (newTab, now - 11 * day), (newFolder, now - 5 * day), (find, now - 40 * day)] {
            var r = ItemRecord(item: item)
            r.phase = .learned
            r.learnedAt = learnedAt
            s.items[r.identity] = r
        }
        var b = ItemRecord(item: build)
        b.phase = .coaching
        b.menuUses = [now.addingTimeInterval(-1 * day), now.addingTimeInterval(-2 * day), now.addingTimeInterval(-3 * day)]
        s.items[b.identity] = b
        var m = ItemRecord(item: closeTab)
        m.phase = .muted
        s.items[m.identity] = m

        s.log = [
            entry(now - 17 * day, .menuUsed, .observed, newTab),
            entry(now - 16 * day, .menuUsed, .observed, reload),
            entry(now - 16 * day + hour, .menuUsed, .observed, newTab),
            entry(now - 15 * day, .menuUsed, .observed, reload),
            entry(now - 15 * day + hour, .menuUsed, .coaching, newTab),
            entry(now - 14 * day, .menuUsed, .coaching, reload),
            entry(now - 14 * day + 2 * hour, .shortcutUsed, .coaching, reload),
            entry(now - 14 * day + 3 * hour, .shortcutUsed, .coaching, newTab),
            entry(now - 14 * day + 4 * hour, .shortcutUsed, .coaching, reload),
            entry(now - 14 * day + 5 * hour, .shortcutUsed, .coaching, newTab),
            entry(now - 12 * day, .shortcutUsed, .learned, reload),
            entry(now - 11 * day, .shortcutUsed, .learned, newTab),
            entry(now - 10 * day, .menuUsed, .observed, newFolder),
            entry(now - 9 * day, .menuUsed, .observed, newFolder),
            entry(now - 8 * day, .menuUsed, .coaching, newFolder),
            entry(now - 8 * day + 2 * hour, .shortcutUsed, .coaching, newFolder),
            entry(now - 8 * day + 4 * hour, .shortcutUsed, .coaching, newFolder),
            entry(now - 5 * day, .shortcutUsed, .learned, newFolder),
            entry(now - 4 * day, .shortcutUsed, .learned, newTab),
            entry(now - 3 * day, .menuUsed, .observed, build),
            entry(now - 3 * day + hour, .menuUsed, .muted, closeTab),
            entry(now - 2 * day, .menuUsed, .observed, build),
            entry(now - 2 * day + hour, .shortcutUsed, .learned, find),
            entry(now - 1 * day, .menuUsed, .coaching, build),
            entry(now - 1 * day + hour, .menuUsed, .muted, closeTab),
            entry(now - hour, .shortcutUsed, .coaching, build),
        ]
        return s
    }

    func testMondayFirstWeekCountsTuesdayAsThisWeek() {
        let stats = Stats.weekly(state: state(), now: now, calendar: calendar(firstWeekday: 2))
        // This week 1 learned, 5 menu clicks, 4 shortcut uses; last week 2, 3 and 4.
        XCTAssertEqual(stats, WeeklyStats(learned: 1, learnedDelta: -1, menuClicksWithShortcut: 5, menuClicksDelta: 2, shortcutsUsed: 4, shortcutsUsedDelta: 0))
    }

    func testSundayFirstWeekStartsToday() {
        let stats = Stats.weekly(state: state(), now: now, calendar: calendar(firstWeekday: 1))
        // Tuesday belongs to last week when weeks start on Sunday: this week holds only
        // this morning's shortcut use; last week 1 learned, 5 menu clicks, 3 shortcut uses.
        XCTAssertEqual(stats, WeeklyStats(learned: 0, learnedDelta: -1, menuClicksWithShortcut: 0, menuClicksDelta: -5, shortcutsUsed: 1, shortcutsUsedDelta: -2))
    }

    /// Learning is read from the log, so a regression (which clears `learnedAt`) or a second
    /// learning never rewrites a week that has been counted, and an item counts once a week.
    func testLearnedKeepsEachWeeksLearningThroughRegressionAndRelearning() {
        typealias Fx = CoachFixtures
        let c = Fx.coach()
        var s = CoachState()
        func learn(onDay day: Double) {
            for i in 0..<3 { _ = c.handle(Fx.key(Fx.reload, at: day * Fx.day + 10 * Fx.hour + Double(i) * 10), state: &s, context: Fx.ctx) }
            XCTAssertEqual(s.items[Fx.reload.identity]?.phase, .learned)
        }
        func regress(onDay day: Double) {
            Fx.use(Fx.reload, times: 5, from: day * Fx.day + 10 * Fx.hour, step: 600, coach: c, state: &s)
            XCTAssertEqual(s.items[Fx.reload.identity]?.phase, .coaching)
        }
        func stats(onDay day: Double) -> WeeklyStats {
            Stats.weekly(state: s, now: Fx.base.addingTimeInterval(day * Fx.day), calendar: Fx.calendar)
        }

        Fx.use(Fx.reload, times: 3, from: 10 * Fx.hour, coach: c, state: &s)  // Mon Oct 12: nudge
        learn(onDay: 1)                                                       // Tue
        regress(onDay: 2)                                                     // Wed
        XCTAssertEqual(stats(onDay: 3).learned, 1, "a regression later in the week keeps the learning")
        learn(onDay: 3)                                                       // Thu
        XCTAssertEqual(stats(onDay: 4).learned, 1, "learned twice in one week counts once")

        regress(onDay: 7)                                                     // Mon Oct 19
        learn(onDay: 8)                                                       // Tue Oct 20
        var week = stats(onDay: 9)
        XCTAssertEqual(week.learned, 1)
        XCTAssertEqual(week.learnedDelta, 0, "last week keeps its own learning")
        regress(onDay: 10)                                                    // Thu Oct 22
        week = stats(onDay: 11)
        XCTAssertEqual(week.learned, 1)
        XCTAssertEqual(week.learnedDelta, 0)
    }

    /// Weeks are half-open: Monday 00:00 belongs to the new week only.
    func testEventsAtTheWeekStartCountOnlyInTheNewWeek() {
        let cal = calendar(firstWeekday: 2)
        let start = Stats.weekInterval(containing: now, calendar: cal).start  // Mon Oct 12 00:00
        var s = CoachState()
        var r = ItemRecord(item: reload)
        r.phase = .learned
        r.learnedAt = start
        s.items[r.identity] = r
        s.log = [
            entry(start - hour, .shortcutUsed, .coaching),
            entry(start, .shortcutUsed, .learned),
            entry(start, .menuUsed, .coaching, build),
        ]
        XCTAssertEqual(Stats.weekly(state: s, now: now, calendar: cal), WeeklyStats(learned: 1, learnedDelta: 1, menuClicksWithShortcut: 1, menuClicksDelta: 1, shortcutsUsed: 1, shortcutsUsedDelta: 0))
    }

    /// Foundation finds no week for the last local hour of each day in the week after Greenland
    /// moves its clocks forward; the start of that day still has one.
    func testWeekIsFoundFromTheDayStartWhenFoundationHasNone() {
        var nuuk = Calendar(identifier: .gregorian)
        nuuk.timeZone = TimeZone(identifier: "America/Nuuk")!
        nuuk.firstWeekday = 2
        let wednesdayNight = Date(timeIntervalSince1970: 1_775_089_800)  // 2026-04-02 00:30 UTC, Wed 23:30 local
        let week = Stats.weekInterval(containing: wednesdayNight, calendar: nuuk)
        XCTAssertEqual(week, DateInterval(
            start: Date(timeIntervalSince1970: 1_774_832_400),  // Mon 2026-03-30 00:00 local
            end: Date(timeIntervalSince1970: 1_775_437_200)  // Mon 2026-04-06 00:00 local
        ))
        var s = CoachState()
        s.log = [entry(Date(timeIntervalSince1970: 1_774_612_800), .menuUsed, .observed)]  // Fri 2026-03-27 12:00 UTC
        let stats = Stats.weekly(state: s, now: wednesdayNight, calendar: nuuk)
        XCTAssertEqual(stats.menuClicksWithShortcut, 0)
        XCTAssertEqual(stats.menuClicksDelta, -1, "last Friday belongs to last week only")
    }

    func testFallBackWeekKeepsItsExtraHour() {
        let ny = newYork()
        let sundayNight = ny.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 23, minute: 45))!
        let thisWeek = Stats.weekInterval(containing: sundayNight, calendar: ny)
        let lastWeek = Stats.weekInterval(containing: thisWeek.start - 1, calendar: ny)
        XCTAssertEqual(thisWeek.start, ny.date(from: DateComponents(year: 2026, month: 10, day: 26)))
        XCTAssertEqual(thisWeek.duration, 169 * hour)
        XCTAssertEqual(lastWeek.end, thisWeek.start)

        var s = CoachState()
        s.log = [
            entry(thisWeek.start - 1, .menuUsed, .observed),  // Sun Oct 25 23:59:59
            entry(thisWeek.start + 1, .menuUsed, .observed),  // Mon Oct 26 00:00:01
            entry(ny.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 23, minute: 30))!, .menuUsed, .observed),
        ]
        let stats = Stats.weekly(state: s, now: sundayNight, calendar: ny)
        XCTAssertEqual(stats.menuClicksWithShortcut, 2, "the week's last hour, after the extra one, is still this week")
        XCTAssertEqual(stats.menuClicksDelta, 1)
    }

    func testWeekAfterFallBackSeesLastWeeksFirstHour() {
        let ny = newYork()
        var s = CoachState()
        s.log = [entry(ny.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 0, minute: 30))!, .menuUsed, .observed)]
        let stats = Stats.weekly(state: s, now: ny.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!, calendar: ny)
        XCTAssertEqual(stats.menuClicksWithShortcut, 0)
        XCTAssertEqual(stats.menuClicksDelta, -1, "last week is 169 hours long, not 7 × 24")
    }

    func testSpringForwardWeekIsAnHourShort() {
        let ny = newYork()
        let week = Stats.weekInterval(containing: ny.date(from: DateComponents(year: 2027, month: 3, day: 14, hour: 12))!, calendar: ny)
        XCTAssertEqual(week.start, ny.date(from: DateComponents(year: 2027, month: 3, day: 8)))
        XCTAssertEqual(week.duration, 167 * hour)
    }

    func testShortcutUsesWhileCoachingCount() {
        var s = CoachState()
        s.log = [entry(now - 2 * day, .shortcutUsed, .coaching), entry(now - 1 * day, .shortcutUsed, .coaching)]
        XCTAssertEqual(Stats.weekly(state: s, now: now, calendar: calendar(firstWeekday: 2)).shortcutsUsed, 2)
    }

    func testMutedMenuUsesStillCount() {
        var s = CoachState()
        s.log = [entry(now - 1 * day, .menuUsed, .muted)]
        XCTAssertEqual(Stats.weekly(state: s, now: now, calendar: calendar(firstWeekday: 2)).menuClicksWithShortcut, 1)
    }

    func testCoachingNowSortsByUseCountAndSkipsSnoozed() {
        var s = state()
        var r = ItemRecord(item: MenuItemRecord(bundleID: "com.apple.Safari", path: ["File", "Print…"], shortcut: Shortcut(modifiers: [.command], key: .character("P"))))
        r.phase = .coaching
        r.menuUses = Array(repeating: now, count: 5)
        s.items[r.identity] = r
        var snoozed = ItemRecord(item: MenuItemRecord(bundleID: "com.apple.Safari", path: ["Edit", "Paste"], shortcut: Shortcut(modifiers: [.command], key: .character("V"))))
        snoozed.phase = .coaching
        snoozed.snoozedUntil = now.addingTimeInterval(day)
        s.items[snoozed.identity] = snoozed

        let list = Stats.coachingNow(state: s, now: now)
        XCTAssertEqual(list.map(\.item.title), ["Print…", "Build"])
    }

    func testCoachingNowBreaksTiesByTitle() {
        var s = CoachState()
        for title in ["Zoom", "Paste", "Open…", "Find…", "Copy", "Bold"] {
            var r = ItemRecord(item: item(title))
            r.phase = .coaching
            r.menuUses = [now - day, now - 2 * day, now - 3 * day]
            s.items[r.identity] = r
        }
        XCTAssertEqual(Stats.coachingNow(state: s, now: now).map(\.item.title), ["Bold", "Copy", "Find…", "Open…", "Paste", "Zoom"])
    }

    func testCoachingNowShowsAnExpiredSnooze() {
        var s = CoachState()
        var r = ItemRecord(item: build)
        r.phase = .coaching
        r.menuUses = [now - day]
        r.snoozedUntil = now  // run out, not yet pruned
        s.items[r.identity] = r
        XCTAssertEqual(Stats.coachingNow(state: s, now: now).map(\.item.title), ["Build"])
    }

    /// Equal sort keys are common across apps ("Close Tab" in every browser). The identity
    /// settles them, so neither a relaunch nor a growing dictionary reorders a list.
    func testTiesKeepOneOrderWhateverTheDictionaryOrder() {
        let apps = ["org.mozilla.firefox", "com.google.Chrome", "com.brave.Browser", "com.apple.Safari", "com.microsoft.edgemac"]
        for round in 0..<8 {
            var s = CoachState()
            for f in 0..<(round * 5) {
                let filler = ItemRecord(item: item("Filler \(f)", bundle: "com.example.filler"))
                s.items[filler.identity] = filler
            }
            for app in round.isMultiple(of: 2) ? apps : apps.reversed() {
                var coaching = ItemRecord(item: item("Close Tab", bundle: app))
                coaching.phase = .coaching
                coaching.menuUses = [now - day, now - 2 * day, now - 3 * day]
                var learned = ItemRecord(item: item("New Tab", bundle: app))
                learned.phase = .learned
                learned.learnedAt = now - day
                var muted = ItemRecord(item: item("Copy", bundle: app, menu: "Edit"))
                muted.phase = .muted
                for r in [coaching, learned, muted] { s.items[r.identity] = r }
            }
            XCTAssertEqual(Stats.grouped(Stats.coachingNow(state: s, now: now)).map(\.bundleID), apps.sorted(), "round \(round)")
            XCTAssertEqual(Stats.learned(state: s).map(\.item.bundleID), apps.sorted(), "round \(round)")
            XCTAssertEqual(Stats.muted(state: s).map(\.item.bundleID), apps.sorted(), "round \(round)")
        }
    }

    /// Menu titles come in many languages: lowercase or accented initials must not sort after "Z".
    func testTitlesSortInLocalizedOrder() {
        var s = CoachState()
        for title in ["Zoom", "Éditer", "about", "Bearbeiten", "Aide"] {
            var muted = ItemRecord(item: item(title, bundle: "com.example.muted"))
            muted.phase = .muted
            var coaching = ItemRecord(item: item(title, bundle: "com.example.coaching"))
            coaching.phase = .coaching
            coaching.menuUses = [now - day]
            for r in [muted, coaching] { s.items[r.identity] = r }
        }
        let expected = ["about", "Aide", "Bearbeiten", "Éditer", "Zoom"]
        XCTAssertEqual(Stats.muted(state: s).map(\.item.title), expected)
        XCTAssertEqual(Stats.coachingNow(state: s, now: now).map(\.item.title), expected)
    }

    func testGroupedKeepsFirstAppearanceOrder() {
        let a = ItemRecord(item: build)
        let b = ItemRecord(item: reload)
        let c = ItemRecord(item: MenuItemRecord(bundleID: "com.apple.dt.Xcode", path: ["Product", "Run"], shortcut: Shortcut(modifiers: [.command], key: .character("R"))))
        let groups = Stats.grouped([a, b, c])
        XCTAssertEqual(groups.map(\.bundleID), ["com.apple.dt.Xcode", "com.apple.Safari"])
        XCTAssertEqual(groups.map { $0.records.map(\.item.title) }, [["Build", "Run"], ["Reload Page"]])
    }

    func testLearnedListKeepsTheTenNewestLearnedOnly() {
        var s = CoachState()
        for i in 0..<12 {
            var r = ItemRecord(item: MenuItemRecord(bundleID: "a", path: ["M", "Item \(i)"], shortcut: Shortcut(modifiers: [.command], key: .character("\(i % 10)"))))
            r.phase = .learned
            r.learnedAt = now.addingTimeInterval(Double(-i) * 3_600)
            s.items[r.identity] = r
        }
        var muted = ItemRecord(item: item("Muted"))
        muted.phase = .muted
        muted.learnedAt = now  // muting keeps learnedAt
        s.items[muted.identity] = muted

        XCTAssertEqual(Stats.learned(state: s, limit: 10).map(\.item.title), (0..<10).map { "Item \($0)" })
        XCTAssertEqual(Stats.learned(state: s).count, 10, "the popover lists the last 10 (spec §7.3)")
        XCTAssertEqual(Stats.learned(state: s, limit: 3).map(\.item.title), ["Item 0", "Item 1", "Item 2"])
        XCTAssertEqual(Stats.learnedCount(state: s), 12, "the section header counts every learned item")
    }

    func testLearnedListPutsUndatedRecordsLast() {
        var s = CoachState()
        var undated = ItemRecord(item: newTab)
        undated.phase = .learned  // learnedAt lost, e.g. a hand-edited file
        var dated = ItemRecord(item: reload)
        dated.phase = .learned
        dated.learnedAt = now - 30 * day
        for r in [undated, dated] { s.items[r.identity] = r }
        XCTAssertEqual(Stats.learned(state: s).map(\.item.title), ["Reload Page", "New Tab"])
    }
}

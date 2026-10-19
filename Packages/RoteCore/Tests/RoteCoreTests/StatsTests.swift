import XCTest
@testable import RoteCore

final class StatsTests: XCTestCase {
    private func calendar(firstWeekday: Int) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = firstWeekday
        return c
    }

    /// Sunday 2026-10-18 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_792_324_800)
    private let day: TimeInterval = 86_400

    private let reload = MenuItemRecord(bundleID: "com.apple.Safari", path: ["View", "Reload Page"], shortcut: Shortcut(modifiers: [.command], key: .character("R")))
    private let build = MenuItemRecord(bundleID: "com.apple.dt.Xcode", path: ["Product", "Build"], shortcut: Shortcut(modifiers: [.command], key: .character("B")))

    private func state() -> CoachState {
        var s = CoachState()
        var r = ItemRecord(item: reload)
        r.phase = .learned
        r.learnedAt = now.addingTimeInterval(-5 * day)            // Tuesday Oct 13
        r.menuUses = [now.addingTimeInterval(-6 * day)]
        s.items[r.identity] = r

        var b = ItemRecord(item: build)
        b.phase = .coaching
        b.menuUses = [now.addingTimeInterval(-1 * day), now.addingTimeInterval(-2 * day), now.addingTimeInterval(-3 * day)]
        s.items[b.identity] = b

        s.log = [
            LogEntry(at: now.addingTimeInterval(-5 * day), kind: .menuUsed, identity: reload.identity, bundleID: reload.bundleID, phaseAfter: .coaching),
            LogEntry(at: now.addingTimeInterval(-4 * day), kind: .shortcutUsed, identity: reload.identity, bundleID: reload.bundleID, phaseAfter: .learned),
            LogEntry(at: now.addingTimeInterval(-1 * day), kind: .menuUsed, identity: build.identity, bundleID: build.bundleID, phaseAfter: .coaching),
            LogEntry(at: now.addingTimeInterval(-9 * day), kind: .menuUsed, identity: build.identity, bundleID: build.bundleID, phaseAfter: .observed),
            LogEntry(at: now.addingTimeInterval(-9 * day), kind: .shortcutUsed, identity: reload.identity, bundleID: reload.bundleID, phaseAfter: .observed),
        ]
        return s
    }

    func testMondayFirstWeekCountsTuesdayAsThisWeek() {
        let stats = Stats.weekly(state: state(), now: now, calendar: calendar(firstWeekday: 2))
        XCTAssertEqual(stats.learned, 1)
        XCTAssertEqual(stats.learnedDelta, 1)
        XCTAssertEqual(stats.menuClicksWithShortcut, 2)
        XCTAssertEqual(stats.menuClicksDelta, 1, "one click last week")
        XCTAssertEqual(stats.shortcutsUsed, 1, "only coaching/learned uses count")
        XCTAssertEqual(stats.shortcutsUsedDelta, 1, "the week-old use was while observed")
    }

    func testSundayFirstWeekStartsToday() {
        let stats = Stats.weekly(state: state(), now: now, calendar: calendar(firstWeekday: 1))
        XCTAssertEqual(stats.learned, 0, "Tuesday belongs to last week when weeks start on Sunday")
        XCTAssertEqual(stats.learnedDelta, -1)
        XCTAssertEqual(stats.menuClicksWithShortcut, 0)
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

    func testGroupedKeepsFirstAppearanceOrder() {
        let a = ItemRecord(item: build)
        let b = ItemRecord(item: reload)
        let c = ItemRecord(item: MenuItemRecord(bundleID: "com.apple.dt.Xcode", path: ["Product", "Run"], shortcut: Shortcut(modifiers: [.command], key: .character("R"))))
        let groups = Stats.grouped([a, b, c])
        XCTAssertEqual(groups.map(\.bundleID), ["com.apple.dt.Xcode", "com.apple.Safari"])
        XCTAssertEqual(groups[0].records.count, 2)
    }

    func testLearnedListIsNewestFirstAndLimited() {
        var s = CoachState()
        for i in 0..<12 {
            var r = ItemRecord(item: MenuItemRecord(bundleID: "a", path: ["M", "Item \(i)"], shortcut: Shortcut(modifiers: [.command], key: .character("\(i % 10)"))))
            r.phase = .learned
            r.learnedAt = now.addingTimeInterval(Double(-i) * 3_600)
            s.items[r.identity] = r
        }
        let learned = Stats.learned(state: s, limit: 10)
        XCTAssertEqual(learned.count, 10)
        XCTAssertEqual(learned.first?.item.title, "Item 0")
    }
}

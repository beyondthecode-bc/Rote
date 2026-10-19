import Foundation
@testable import RoteCore

/// Fixtures shared by `CoachTests`, `CoachRulesTests` and `StateStoreTests`: one UTC, Monday-first
/// calendar and one fixed "now", so every expectation reads against the same clock.
enum CoachFixtures {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }()

    /// 2026-10-12 00:00:00 UTC, a Monday.
    static let base = Date(timeIntervalSince1970: 1_791_763_200)
    static let hour: TimeInterval = 3_600
    static let day: TimeInterval = 86_400

    static let reload = MenuItemRecord(bundleID: "com.apple.Safari", path: ["View", "Reload Page"], shortcut: Shortcut(modifiers: [.command], key: .character("R")))
    static let printItem = MenuItemRecord(bundleID: "com.apple.Safari", path: ["File", "Print…"], shortcut: Shortcut(modifiers: [.command], key: .character("P")))
    static let paste = MenuItemRecord(bundleID: "com.apple.Safari", path: ["Edit", "Paste"], shortcut: Shortcut(modifiers: [.command], key: .character("V")))
    static let ctx = CoachContext()

    static func coach(_ policy: CoachPolicy = .default) -> Coach { Coach(policy: policy, calendar: calendar) }

    static func menu(_ item: MenuItemRecord, at offset: TimeInterval) -> CoachEvent {
        CoachEvent(kind: .menuUsed, item: item, at: base.addingTimeInterval(offset))
    }

    static func key(_ item: MenuItemRecord, at offset: TimeInterval) -> CoachEvent {
        CoachEvent(kind: .shortcutUsed, item: item, at: base.addingTimeInterval(offset))
    }

    /// Drives `count` menu uses `step` seconds apart starting at `start`; returns the last decision.
    @discardableResult
    static func use(_ item: MenuItemRecord, times count: Int, from start: TimeInterval, step: TimeInterval = 10, coach c: Coach, state: inout CoachState, context: CoachContext? = nil) -> CoachDecision {
        var last: CoachDecision = .ignore
        for i in 0..<count {
            last = c.handle(menu(item, at: start + Double(i) * step), state: &state, context: context ?? ctx)
        }
        return last
    }

    /// Every persisted field set to a distinct, non-default value, on whole seconds so ISO 8601
    /// round-trips exactly: a regressed item learned again, a snoozed lesson, a muted item,
    /// both kinds of log entry, a day counter and the global nudge clock.
    static func everyFieldState() -> CoachState {
        func at(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }
        var relearned = ItemRecord(item: reload)
        relearned.phase = .learned
        relearned.menuUses = [at(300), at(700), at(800), at(900), at(1_000)]
        relearned.shortcutUses = [at(400), at(500), at(600)]
        relearned.menuUsesSinceLastNudge = 4
        relearned.shortcutUsesSinceCoaching = 3
        relearned.nudgeCount = 2
        relearned.regressions = 1
        relearned.lastNudgeAt = at(300)
        relearned.learnedAt = at(600)
        var snoozed = ItemRecord(item: printItem)
        snoozed.phase = .coaching
        snoozed.menuUses = [at(1_100), at(1_200), at(1_300)]
        snoozed.shortcutUses = [at(1_400)]
        snoozed.shortcutUsesSinceCoaching = 1
        snoozed.nudgeCount = 1
        snoozed.lastNudgeAt = at(1_300)
        snoozed.snoozedUntil = at(7 * day)
        var muted = ItemRecord(item: paste)
        muted.phase = .muted
        muted.menuUses = [at(1_500), at(1_600)]
        muted.menuUsesSinceLastNudge = 2
        var s = CoachState()
        s.items = [relearned.identity: relearned, snoozed.identity: snoozed, muted.identity: muted]
        s.log = [
            LogEntry(at: at(1_000), kind: .menuUsed, identity: reload.identity, bundleID: reload.bundleID, phaseAfter: .learned),
            LogEntry(at: at(1_400), kind: .shortcutUsed, identity: printItem.identity, bundleID: printItem.bundleID, phaseAfter: .coaching)
        ]
        s.nudgesByDay = ["2026-10-12": 3]
        s.lastNudgeAt = at(1_300)
        return s
    }

    /// `everyFieldState()` as the version 1 file: sorted keys, ISO 8601 dates, no pretty printing.
    /// `CoachRulesTests` pins the encoder and decoder against it; `StateStoreTests` loads it
    /// through the store, so the store's own date strategy is pinned too.
    static let versionOneGolden = """
    {"items":{"com.apple.Safari|Edit›Paste":{"item":{"bundleID":"com.apple.Safari","hasUnrenderableShortcut":false,"isEnabled":true,"path":["Edit","Paste"],"shortcut":{"key":{"character":{"_0":"V"}},"modifiers":8}},
    "menuUses":["2026-10-12T00:25:00Z","2026-10-12T00:26:40Z"],"menuUsesSinceLastNudge":2,"nudgeCount":0,"phase":"muted","regressions":0,
    "shortcutUses":[],"shortcutUsesSinceCoaching":0},
    "com.apple.Safari|File›Print…":{"item":{"bundleID":"com.apple.Safari","hasUnrenderableShortcut":false,"isEnabled":true,"path":["File","Print…"],"shortcut":{"key":{"character":{"_0":"P"}},"modifiers":8}},
    "lastNudgeAt":"2026-10-12T00:21:40Z",
    "menuUses":["2026-10-12T00:18:20Z","2026-10-12T00:20:00Z","2026-10-12T00:21:40Z"],"menuUsesSinceLastNudge":0,"nudgeCount":1,"phase":"coaching","regressions":0,
    "shortcutUses":["2026-10-12T00:23:20Z"],"shortcutUsesSinceCoaching":1,"snoozedUntil":"2026-10-19T00:00:00Z"},
    "com.apple.Safari|View›Reload Page":{"item":{"bundleID":"com.apple.Safari","hasUnrenderableShortcut":false,"isEnabled":true,"path":["View","Reload Page"],"shortcut":{"key":{"character":{"_0":"R"}},"modifiers":8}},
    "lastNudgeAt":"2026-10-12T00:05:00Z","learnedAt":"2026-10-12T00:10:00Z",
    "menuUses":["2026-10-12T00:05:00Z","2026-10-12T00:11:40Z","2026-10-12T00:13:20Z","2026-10-12T00:15:00Z","2026-10-12T00:16:40Z"],"menuUsesSinceLastNudge":4,"nudgeCount":2,"phase":"learned","regressions":1,
    "shortcutUses":["2026-10-12T00:06:40Z","2026-10-12T00:08:20Z","2026-10-12T00:10:00Z"],"shortcutUsesSinceCoaching":3}},
    "lastNudgeAt":"2026-10-12T00:21:40Z",
    "log":[{"at":"2026-10-12T00:16:40Z","bundleID":"com.apple.Safari","identity":"com.apple.Safari|View›Reload Page","kind":"menuUsed","phaseAfter":"learned"},
    {"at":"2026-10-12T00:23:20Z","bundleID":"com.apple.Safari","identity":"com.apple.Safari|File›Print…","kind":"shortcutUsed","phaseAfter":"coaching"}],
    "nudgesByDay":{"2026-10-12":3},"schemaVersion":1}
    """.replacingOccurrences(of: "\n", with: "")
}

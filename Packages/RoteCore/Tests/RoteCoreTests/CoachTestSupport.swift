import Foundation
@testable import RoteCore

/// Fixtures shared by `CoachTests` and `CoachRulesTests`: one UTC, Monday-first calendar and
/// one fixed "now", so every expectation in both files reads against the same clock.
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
}

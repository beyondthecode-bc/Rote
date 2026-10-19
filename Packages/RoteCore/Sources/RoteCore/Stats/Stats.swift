import Foundation

public struct WeeklyStats: Sendable, Equatable {
    public var learned: Int
    public var learnedDelta: Int
    public var menuClicksWithShortcut: Int
    public var menuClicksDelta: Int
    public var shortcutsUsed: Int
    public var shortcutsUsedDelta: Int
}

public struct AppGroup: Sendable, Equatable {
    public var bundleID: String
    public var records: [ItemRecord]
}

/// Read-only views over `CoachState` for the popover (spec §6.5).
public enum Stats {
    public static func weekInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: date.addingTimeInterval(-7 * 86_400), duration: 7 * 86_400)
    }

    public static func weekly(state: CoachState, now: Date, calendar: Calendar) -> WeeklyStats {
        let thisWeek = weekInterval(containing: now, calendar: calendar)
        let lastWeek = weekInterval(containing: thisWeek.start.addingTimeInterval(-1), calendar: calendar)

        func learned(in interval: DateInterval) -> Int {
            state.items.values.filter { $0.learnedAt.map(interval.contains) ?? false }.count
        }
        func menuClicks(in interval: DateInterval) -> Int {
            state.log.filter { $0.kind == .menuUsed && interval.contains($0.at) }.count
        }
        func shortcutUses(in interval: DateInterval) -> Int {
            state.log.filter { $0.kind == .shortcutUsed && ($0.phaseAfter == .coaching || $0.phaseAfter == .learned) && interval.contains($0.at) }.count
        }

        let l = learned(in: thisWeek), lPrev = learned(in: lastWeek)
        let m = menuClicks(in: thisWeek), mPrev = menuClicks(in: lastWeek)
        let s = shortcutUses(in: thisWeek), sPrev = shortcutUses(in: lastWeek)
        return WeeklyStats(
            learned: l, learnedDelta: l - lPrev,
            menuClicksWithShortcut: m, menuClicksDelta: m - mPrev,
            shortcutsUsed: s, shortcutsUsedDelta: s - sPrev
        )
    }

    /// Items being coached, busiest first, snoozed ones hidden.
    public static func coachingNow(state: CoachState, now: Date) -> [ItemRecord] {
        state.items.values
            .filter { $0.phase == .coaching && !$0.isSnoozed(at: now) }
            .sorted {
                if $0.menuUses.count != $1.menuUses.count { return $0.menuUses.count > $1.menuUses.count }
                return $0.item.title < $1.item.title
            }
    }

    public static func learned(state: CoachState, limit: Int = 10) -> [ItemRecord] {
        Array(
            state.items.values
                .filter { $0.phase == .learned }
                .sorted { ($0.learnedAt ?? .distantPast) > ($1.learnedAt ?? .distantPast) }
                .prefix(limit)
        )
    }

    public static func muted(state: CoachState) -> [ItemRecord] {
        state.items.values.filter { $0.phase == .muted }.sorted { $0.item.title < $1.item.title }
    }

    /// Groups by app in order of first appearance, preserving the input order inside each group.
    public static func grouped(_ records: [ItemRecord]) -> [AppGroup] {
        var order: [String] = []
        var buckets: [String: [ItemRecord]] = [:]
        for record in records {
            let id = record.item.bundleID
            if buckets[id] == nil { order.append(id) }
            buckets[id, default: []].append(record)
        }
        return order.map { AppGroup(bundleID: $0, records: buckets[$0] ?? []) }
    }
}

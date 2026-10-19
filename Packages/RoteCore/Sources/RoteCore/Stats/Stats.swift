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
    /// Foundation finds no week for the last local hour of each day in the week after
    /// Greenland moves its clocks forward; the start of that day still has one.
    public static func weekInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)
            ?? calendar.dateInterval(of: .weekOfYear, for: calendar.startOfDay(for: date))
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 86_400)
    }

    public static func weekly(state: CoachState, now: Date, calendar: Calendar) -> WeeklyStats {
        let thisWeek = weekInterval(containing: now, calendar: calendar)
        let lastWeek = weekInterval(containing: thisWeek.start.addingTimeInterval(-1), calendar: calendar)

        // Half-open: `DateInterval.contains` includes the end, which is the next week's start.
        func within(_ date: Date, _ interval: DateInterval) -> Bool {
            interval.start <= date && date < interval.end
        }
        // Items the log shows entering `learned`: a shortcut use that left the item learned
        // after an entry that did not. The log keeps every transition; `learnedAt` does not
        // survive a regression or an unmute.
        func learned(in interval: DateInterval) -> Int {
            var previous: [String: ItemPhase] = [:]
            var entered = Set<String>()
            for entry in state.log {            // append order is event order
                defer { previous[entry.identity] = entry.phaseAfter }
                guard entry.kind == .shortcutUsed, entry.phaseAfter == .learned,
                      let before = previous[entry.identity], before != .learned,
                      within(entry.at, interval) else { continue }
                entered.insert(entry.identity)
            }
            return entered.count
        }
        func menuClicks(in interval: DateInterval) -> Int {
            state.log.filter { $0.kind == .menuUsed && within($0.at, interval) }.count
        }
        func shortcutUses(in interval: DateInterval) -> Int {
            state.log.filter { $0.kind == .shortcutUsed && ($0.phaseAfter == .coaching || $0.phaseAfter == .learned) && within($0.at, interval) }.count
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
                return byTitle($0, $1)
            }
    }

    /// The newest learned items, undated ones last.
    public static func learned(state: CoachState, limit: Int = 10) -> [ItemRecord] {
        Array(
            state.items.values
                .filter { $0.phase == .learned }
                .sorted {
                    let a = $0.learnedAt ?? .distantPast, b = $1.learnedAt ?? .distantPast
                    return a != b ? a > b : $0.identity < $1.identity
                }
                .prefix(limit)
        )
    }

    /// Every learned item; `learned(state:limit:)` lists only the newest.
    public static func learnedCount(state: CoachState) -> Int {
        state.items.values.reduce(0) { $0 + ($1.phase == .learned ? 1 : 0) }
    }

    public static func muted(state: CoachState) -> [ItemRecord] {
        state.items.values.filter { $0.phase == .muted }.sorted(by: byTitle)
    }

    /// Titles in the order a reader expects (case ignored, accented letters beside their base
    /// letter, "9" before "10"), then identity, so equal titles from different apps keep one
    /// order whatever order the dictionary yields.
    private static func byTitle(_ a: ItemRecord, _ b: ItemRecord) -> Bool {
        switch a.item.title.localizedStandardCompare(b.item.title) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return a.identity < b.identity
        }
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

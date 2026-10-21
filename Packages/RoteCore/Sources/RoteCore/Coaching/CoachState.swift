import Foundation

public enum ItemPhase: String, Codable, Sendable {
    case observed, coaching, learned, muted

    /// Precedence when two records for one item must be merged: explicit user decisions first.
    var mergeRank: Int {
        switch self {
        case .muted: return 3
        case .learned: return 2
        case .coaching: return 1
        case .observed: return 0
        }
    }
}

/// Everything Rote remembers about one menu item.
public struct ItemRecord: Codable, Sendable, Equatable, Identifiable {
    /// Shortcut uses kept per item; older ones are dropped, so a heavily used shortcut
    /// cannot grow the state file.
    public static let maxShortcutUses = 50
    /// Menu uses kept per item, the same way. The policy's thresholds are single digits, so
    /// the latest fifty are all the coach ever counts.
    public static let maxMenuUses = 50
    /// The largest value any stored counter may carry. A lifetime of coaching stays far below
    /// it, and far enough below `Int.max` that every increment and merge after loading is safe.
    public static let maxCounter = 1_000_000

    /// Last seen record: title, shortcut, enabled state.
    public var item: MenuItemRecord
    public var phase: ItemPhase
    /// Menu uses inside the policy window (pruned on every event).
    public var menuUses: [Date]
    public var shortcutUses: [Date]
    public var menuUsesSinceLastNudge: Int
    public var shortcutUsesSinceCoaching: Int
    public var nudgeCount: Int
    /// Times the item went learned → coaching. Gentler cadence once > 0.
    public var regressions: Int
    public var lastNudgeAt: Date?
    public var snoozedUntil: Date?
    public var learnedAt: Date?

    public init(item: MenuItemRecord) {
        self.item = item
        phase = .observed
        menuUses = []
        shortcutUses = []
        menuUsesSinceLastNudge = 0
        shortcutUsesSinceCoaching = 0
        nudgeCount = 0
        regressions = 0
        lastNudgeAt = nil
        snoozedUntil = nil
        learnedAt = nil
    }

    private enum CodingKeys: String, CodingKey {
        case item, phase, menuUses, shortcutUses, menuUsesSinceLastNudge, shortcutUsesSinceCoaching
        case nudgeCount, regressions, lastNudgeAt, snoozedUntil, learnedAt
    }

    /// Tolerant on read: a file written by an older build, or edited by hand, may lack any
    /// field but the item. Missing fields take the values of a fresh record. The file is
    /// user-writable, so counters are clamped to `0...maxCounter` and use lists to their caps
    /// (the latest survive); what had to be clamped, or was too long to be a file Rote wrote,
    /// is told to the decoder's `CoachStateDecodingReport`, if it carries one (audit M1).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let report = CoachStateDecodingReport.from(decoder)
        item = try c.decode(MenuItemRecord.self, forKey: .item)
        phase = try c.decodeIfPresent(ItemPhase.self, forKey: .phase) ?? .observed
        menuUses = try c.decodeDates(forKey: .menuUses, keeping: Self.maxMenuUses, report: report)
        shortcutUses = try c.decodeDates(forKey: .shortcutUses, keeping: Self.maxShortcutUses, report: report)
        menuUsesSinceLastNudge = try c.decodeCounter(forKey: .menuUsesSinceLastNudge, report: report)
        shortcutUsesSinceCoaching = try c.decodeCounter(forKey: .shortcutUsesSinceCoaching, report: report)
        nudgeCount = try c.decodeCounter(forKey: .nudgeCount, report: report)
        regressions = try c.decodeCounter(forKey: .regressions, report: report)
        lastNudgeAt = try c.decodeIfPresent(Date.self, forKey: .lastNudgeAt)
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        learnedAt = try c.decodeIfPresent(Date.self, forKey: .learnedAt)
    }

    /// Always the item's current identity, so an identity-rule change cannot strand a record.
    public var identity: String { item.identity }
    public var id: String { identity }

    public func isSnoozed(at now: Date) -> Bool {
        guard let until = snoozedUntil else { return false }
        return until > now
    }
}

public struct CoachEvent: Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case menuUsed, shortcutUsed
    }
    public var kind: Kind
    public var item: MenuItemRecord
    public var at: Date

    public init(kind: Kind, item: MenuItemRecord, at: Date) {
        self.kind = kind
        self.item = item
        self.at = at
    }
}

/// One line of history, enough for weekly statistics.
public struct LogEntry: Codable, Sendable, Equatable {
    public var at: Date
    public var kind: CoachEvent.Kind
    public var identity: String
    public var bundleID: String
    public var phaseAfter: ItemPhase

    public init(at: Date, kind: CoachEvent.Kind, identity: String, bundleID: String, phaseAfter: ItemPhase) {
        self.at = at
        self.kind = kind
        self.identity = identity
        self.bundleID = bundleID
        self.phaseAfter = phaseAfter
    }

    private enum CodingKeys: String, CodingKey {
        case at, kind, identity, bundleID, phaseAfter
    }

    /// Tolerant on read, like `ItemRecord`: only the time and the kind are required.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decode(Date.self, forKey: .at)
        kind = try c.decode(CoachEvent.Kind.self, forKey: .kind)
        identity = try c.decodeIfPresent(String.self, forKey: .identity) ?? ""
        bundleID = try c.decodeIfPresent(String.self, forKey: .bundleID) ?? ""
        phaseAfter = try c.decodeIfPresent(ItemPhase.self, forKey: .phaseAfter) ?? .observed
    }
}

/// Runtime conditions the engine knows and the coach does not store.
public struct CoachContext: Sendable, Equatable {
    public var isPaused: Bool
    public var isAppExcluded: Bool
    public var isAppPaused: Bool
    public var isNudgeOnScreen: Bool
    public var isOverlayVisible: Bool
    public var ownBundleID: String

    public init(
        isPaused: Bool = false,
        isAppExcluded: Bool = false,
        isAppPaused: Bool = false,
        isNudgeOnScreen: Bool = false,
        isOverlayVisible: Bool = false,
        ownBundleID: String = "com.beyondthecode.rote"
    ) {
        self.isPaused = isPaused
        self.isAppExcluded = isAppExcluded
        self.isAppPaused = isAppPaused
        self.isNudgeOnScreen = isNudgeOnScreen
        self.isOverlayVisible = isOverlayVisible
        self.ownBundleID = ownBundleID
    }
}

public enum CoachDecision: Sendable, Equatable {
    case nudge(ItemRecord)
    case record
    case ignore
}

/// What a tolerant decode of `CoachState` had to clamp or drop. A decoder whose `userInfo`
/// carries one under `CoachState.decodingReportKey` is told; without one the values are
/// clamped silently. `StateStore` quarantines a file that produced any issue: a value a Rote
/// never wrote is a tampered or corrupt file, not one to coach from.
public final class CoachStateDecodingReport: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    public init() {}

    public var issues: [String] { lock.withLock { recorded } }
    public var isEmpty: Bool { issues.isEmpty }

    func note(_ issue: String) { lock.withLock { recorded.append(issue) } }

    static func from(_ decoder: any Decoder) -> CoachStateDecodingReport? {
        decoder.userInfo[CoachState.decodingReportKey] as? CoachStateDecodingReport
    }
}

extension KeyedDecodingContainer {
    /// A counter clamped to `0...ItemRecord.maxCounter`; a value outside it is reported.
    func decodeCounter(forKey key: Key, report: CoachStateDecodingReport?) throws -> Int {
        let raw = try decodeIfPresent(Int.self, forKey: key) ?? 0
        guard (0...ItemRecord.maxCounter).contains(raw) else {
            report?.note("\(key.stringValue) out of range: \(raw)")
            return min(max(raw, 0), ItemRecord.maxCounter)
        }
        return raw
    }

    /// Dates sorted, the latest `limit` of them. A list longer than any Rote writes
    /// (`CoachState.maxDecodedCollectionCount`) is dropped without parsing a single date and reported.
    func decodeDates(forKey key: Key, keeping limit: Int, report: CoachStateDecodingReport?) throws -> [Date] {
        guard try isOversized(key, report: report) == false else { return [] }
        let dates = try decodeIfPresent([Date].self, forKey: key) ?? []
        guard dates.count > limit else { return dates }
        return Array(dates.sorted().suffix(limit))
    }

    /// The last `limit` elements in file order, which is append order for the log.
    func decodeEntries<Element: Decodable>(_: Element.Type, forKey key: Key, keeping limit: Int, report: CoachStateDecodingReport?) throws -> [Element] {
        guard try isOversized(key, report: report) == false else { return [] }
        let entries = try decodeIfPresent([Element].self, forKey: key) ?? []
        guard entries.count > limit else { return entries }
        return Array(entries.suffix(limit))
    }

    /// A dictionary, or `[:]` when it holds more entries than any Rote writes.
    func decodeDictionary<Value: Decodable>(_: Value.Type, forKey key: Key, report: CoachStateDecodingReport?) throws -> [String: Value] {
        guard contains(key), try !decodeNil(forKey: key) else { return [:] }
        let keys = try nestedContainer(keyedBy: AnyCodingKey.self, forKey: key).allKeys.count
        guard keys <= CoachState.maxDecodedCollectionCount else {
            report?.note("\(key.stringValue) has \(keys) entries")
            return [:]
        }
        return try decode([String: Value].self, forKey: key)
    }

    /// True when `key` holds an array longer than `CoachState.maxDecodedCollectionCount`; the
    /// array's elements are not read. False for a missing or null key.
    private func isOversized(_ key: Key, report: CoachStateDecodingReport?) throws -> Bool {
        guard contains(key), try !decodeNil(forKey: key) else { return false }
        let container = try nestedUnkeyedContainer(forKey: key)
        guard let count = container.count, count > CoachState.maxDecodedCollectionCount else { return false }
        report?.note("\(key.stringValue) has \(count) entries")
        return true
    }
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// The persisted whole (spec §10). `schemaVersion` guards future migrations.
public struct CoachState: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    /// `JSONDecoder.userInfo` key for the `CoachStateDecodingReport` a decode fills in.
    public static let decodingReportKey = CodingUserInfoKey(rawValue: "com.beyondthecode.rote.coachStateDecodingReport")!
    /// Log entries kept on load, the latest first to go: a month of heavy use is a few thousand.
    public static let maxLogEntries = 50_000
    /// More entries than this in any one array or dictionary is not a file Rote wrote: the
    /// collection is dropped unread and reported, so a crafted file cannot make the load crawl.
    public static let maxDecodedCollectionCount = 1_000_000

    public var schemaVersion: Int
    public var items: [String: ItemRecord]
    public var log: [LogEntry]
    /// "yyyy-MM-dd" → nudges shown that local day.
    public var nudgesByDay: [String: Int]
    public var lastNudgeAt: Date?

    public init() {
        schemaVersion = Self.currentSchemaVersion
        items = [:]
        log = []
        nudgesByDay = [:]
        lastNudgeAt = nil
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, items, log, nudgesByDay, lastNudgeAt
    }

    /// Tolerant on read, like `ItemRecord`. A file without a version is version 1. Oversized
    /// collections are dropped and day counters clamped, both reported (see `ItemRecord`); so are
    /// records of one identity whose counters no merge can hold within the cap.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let report = CoachStateDecodingReport.from(decoder)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        items = try c.decodeDictionary(ItemRecord.self, forKey: .items, report: report)
        log = try c.decodeEntries(LogEntry.self, forKey: .log, keeping: Self.maxLogEntries, report: report)
        nudgesByDay = try c.decodeDictionary(Int.self, forKey: .nudgesByDay, report: report).mapValues { value in
            guard (0...ItemRecord.maxCounter).contains(value) else {
                report?.note("nudgesByDay out of range: \(value)")
                return min(max(value, 0), ItemRecord.maxCounter)
            }
            return value
        }
        lastNudgeAt = try c.decodeIfPresent(Date.self, forKey: .lastNudgeAt)
        if let report { Self.reportUnmergeableCollisions(in: items, to: report) }
    }

    /// Records that `rekeyItems()` will merge add their nudge and regression counts; a sum past
    /// the cap is clamped there, so a file whose records add up past it would lose counts and
    /// cannot be one Rote wrote. Decoded counters are already within `0...maxCounter`, so the
    /// sums cannot overflow.
    private static func reportUnmergeableCollisions(in items: [String: ItemRecord], to report: CoachStateDecodingReport) {
        var nudges: [String: Int] = [:]
        var regressions: [String: Int] = [:]
        for record in items.values {
            nudges[record.identity, default: 0] += record.nudgeCount
            regressions[record.identity, default: 0] += record.regressions
        }
        for (identity, total) in nudges where total > ItemRecord.maxCounter || regressions[identity, default: 0] > ItemRecord.maxCounter {
            report.note("items for one identity exceed the counter cap: \(identity)")
        }
    }

    /// Re-keys `items` by each record's current identity, merging duplicates that an
    /// identity-rule change may have produced. Call once after loading from disk.
    public mutating func rekeyItems() {
        var merged: [String: ItemRecord] = [:]
        for (_, record) in items.sorted(by: { $0.key < $1.key }) {
            let key = record.identity
            merged[key] = merged[key].map { Self.merge($0, record) } ?? record
        }
        items = merged
    }

    /// The record that carries more of the user's decisions wins (muted, then learned,
    /// then coaching); busyness breaks ties; an exact tie keeps the first by key order.
    /// Nothing the user would notice is dropped: snoozes, histories and counts carry over.
    /// Menu uses since the last nudge (or since learning) are recounted against the merged
    /// clock, so a loser's later nudge cannot be followed by a nudge on the very next use.
    static func merge(_ a: ItemRecord, _ b: ItemRecord) -> ItemRecord {
        let aWins: Bool
        if a.phase.mergeRank != b.phase.mergeRank {
            aWins = a.phase.mergeRank > b.phase.mergeRank
        } else {
            aWins = (a.menuUses.count + a.shortcutUses.count) >= (b.menuUses.count + b.shortcutUses.count)
        }
        var winner = aWins ? a : b
        let loser = aWins ? b : a
        winner.menuUses = Array((winner.menuUses + loser.menuUses).sorted().suffix(ItemRecord.maxMenuUses))
        winner.shortcutUses = Array((winner.shortcutUses + loser.shortcutUses).sorted().suffix(ItemRecord.maxShortcutUses))
        winner.nudgeCount = saturatingSum(winner.nudgeCount, loser.nudgeCount)
        winner.regressions = saturatingSum(winner.regressions, loser.regressions)
        winner.lastNudgeAt = later(winner.lastNudgeAt, loser.lastNudgeAt)
        winner.snoozedUntil = later(winner.snoozedUntil, loser.snoozedUntil)
        if winner.phase == .learned { winner.learnedAt = winner.learnedAt ?? loser.learnedAt }
        let since = [winner.lastNudgeAt, winner.phase == .learned ? winner.learnedAt : nil].compactMap { $0 }.max()
        if let since { winner.menuUsesSinceLastNudge = winner.menuUses.filter { $0 > since }.count }
        winner.shortcutUsesSinceCoaching = max(winner.shortcutUsesSinceCoaching, loser.shortcutUsesSinceCoaching)
        return winner
    }

    /// `a + b` held within `0...ItemRecord.maxCounter`: two records of one identity in a
    /// tampered file must merge, never trap (audit M1).
    static func saturatingSum(_ a: Int, _ b: Int) -> Int {
        let (sum, overflow) = max(a, 0).addingReportingOverflow(max(b, 0))
        return overflow ? ItemRecord.maxCounter : min(sum, ItemRecord.maxCounter)
    }

    private static func later(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case (let a?, let b?): return max(a, b)
        case (let a?, nil): return a
        case (nil, let b?): return b
        case (nil, nil): return nil
        }
    }
}

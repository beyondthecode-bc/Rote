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
    /// field but the item. Missing fields take the values of a fresh record.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        item = try c.decode(MenuItemRecord.self, forKey: .item)
        phase = try c.decodeIfPresent(ItemPhase.self, forKey: .phase) ?? .observed
        menuUses = try c.decodeIfPresent([Date].self, forKey: .menuUses) ?? []
        shortcutUses = try c.decodeIfPresent([Date].self, forKey: .shortcutUses) ?? []
        menuUsesSinceLastNudge = try c.decodeIfPresent(Int.self, forKey: .menuUsesSinceLastNudge) ?? 0
        shortcutUsesSinceCoaching = try c.decodeIfPresent(Int.self, forKey: .shortcutUsesSinceCoaching) ?? 0
        nudgeCount = try c.decodeIfPresent(Int.self, forKey: .nudgeCount) ?? 0
        regressions = try c.decodeIfPresent(Int.self, forKey: .regressions) ?? 0
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

/// The persisted whole (spec §10). `schemaVersion` guards future migrations.
public struct CoachState: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

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

    /// Tolerant on read, like `ItemRecord`. A file without a version is version 1.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        items = try c.decodeIfPresent([String: ItemRecord].self, forKey: .items) ?? [:]
        log = try c.decodeIfPresent([LogEntry].self, forKey: .log) ?? []
        nudgesByDay = try c.decodeIfPresent([String: Int].self, forKey: .nudgesByDay) ?? [:]
        lastNudgeAt = try c.decodeIfPresent(Date.self, forKey: .lastNudgeAt)
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
        winner.menuUses = (winner.menuUses + loser.menuUses).sorted()
        winner.shortcutUses = Array((winner.shortcutUses + loser.shortcutUses).sorted().suffix(ItemRecord.maxShortcutUses))
        winner.nudgeCount += loser.nudgeCount
        winner.regressions += loser.regressions
        winner.lastNudgeAt = later(winner.lastNudgeAt, loser.lastNudgeAt)
        winner.snoozedUntil = later(winner.snoozedUntil, loser.snoozedUntil)
        if winner.phase == .learned { winner.learnedAt = winner.learnedAt ?? loser.learnedAt }
        let since = [winner.lastNudgeAt, winner.phase == .learned ? winner.learnedAt : nil].compactMap { $0 }.max()
        if let since { winner.menuUsesSinceLastNudge = winner.menuUses.filter { $0 > since }.count }
        winner.shortcutUsesSinceCoaching = max(winner.shortcutUsesSinceCoaching, loser.shortcutUsesSinceCoaching)
        return winner
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

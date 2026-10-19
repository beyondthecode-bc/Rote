import Foundation

/// Every tunable of the patient coach (spec §6.4). Settings mirror the first five.
public struct CoachPolicy: Codable, Sendable, Equatable {
    /// Menu uses within `window` before the first nudge.
    public var nudgeAfter: Int
    /// Rolling window for counting menu uses.
    public var window: TimeInterval
    /// Minimum time between two nudges for the same item.
    public var itemSpacing: TimeInterval
    /// Minimum time between any two nudges.
    public var globalSpacing: TimeInterval
    /// Maximum nudges per local calendar day.
    public var dailyCap: Int
    /// Shortcut uses while coaching before the item counts as learned.
    public var learnAfter: Int
    /// Menu uses after learning before coaching resumes.
    public var regressAfter: Int
    /// How long log entries and day counters are kept.
    public var logRetention: TimeInterval

    public init(
        nudgeAfter: Int = 3,
        window: TimeInterval = 7 * 86_400,
        itemSpacing: TimeInterval = 4 * 3_600,
        globalSpacing: TimeInterval = 90,
        dailyCap: Int = 12,
        learnAfter: Int = 3,
        regressAfter: Int = 5,
        logRetention: TimeInterval = 30 * 86_400
    ) {
        self.nudgeAfter = nudgeAfter
        self.window = window
        self.itemSpacing = itemSpacing
        self.globalSpacing = globalSpacing
        self.dailyCap = dailyCap
        self.learnAfter = learnAfter
        self.regressAfter = regressAfter
        self.logRetention = logRetention
    }

    public static let `default` = CoachPolicy()
}

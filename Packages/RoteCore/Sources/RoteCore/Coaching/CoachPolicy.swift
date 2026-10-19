import Foundation

/// Every tunable of the patient coach (spec §6.4). Settings mirror `nudgeAfter`,
/// `itemSpacing` and `dailyCap`. Values are clamped to sane minimums and immutable
/// once built, so a bad preference cannot disable the coach. Nothing persists a policy.
public struct CoachPolicy: Sendable, Equatable {
    /// Menu uses within `window` before the first nudge.
    public let nudgeAfter: Int
    /// Rolling window for counting menu uses.
    public let window: TimeInterval
    /// Minimum time between two nudges for the same item.
    public let itemSpacing: TimeInterval
    /// Minimum time between any two nudges.
    public let globalSpacing: TimeInterval
    /// Maximum nudges per local calendar day.
    public let dailyCap: Int
    /// Shortcut uses while coaching before the item counts as learned.
    public let learnAfter: Int
    /// Menu uses after learning before coaching resumes.
    public let regressAfter: Int
    /// How long log entries and day counters are kept.
    public let logRetention: TimeInterval

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
        self.nudgeAfter = max(1, nudgeAfter)
        self.window = max(60, window)
        self.itemSpacing = max(0, itemSpacing)
        self.globalSpacing = max(0, globalSpacing)
        self.dailyCap = max(1, dailyCap)
        self.learnAfter = max(1, learnAfter)
        self.regressAfter = max(1, regressAfter)
        self.logRetention = max(86_400, logRetention)
    }

    public static let `default` = CoachPolicy()
}

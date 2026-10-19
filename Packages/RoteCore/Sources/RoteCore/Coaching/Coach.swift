import Foundation

/// The patient coach (spec §6). Pure: same events, same state, same answers.
public struct Coach: Sendable {
    public var policy: CoachPolicy
    public let calendar: Calendar
    /// Day keys are always Gregorian, in `calendar`'s time zone (see `dayKey`).
    private let dayCalendar: Calendar

    public init(policy: CoachPolicy = .default, calendar: Calendar = .current) {
        self.policy = policy
        self.calendar = calendar
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        dayCalendar = gregorian
    }

    // MARK: - Events

    public func handle(_ event: CoachEvent, state: inout CoachState, context: CoachContext) -> CoachDecision {
        let item = event.item
        let now = event.at
        if item.bundleID == context.ownBundleID || context.isAppExcluded { return .ignore }
        guard item.isCoachable else { return .ignore }

        var record = state.items[item.identity] ?? ItemRecord(item: item)
        record.item = item
        prune(&record, now: now)

        switch event.kind {
        case .menuUsed:
            record.menuUses.append(now)
            record.menuUsesSinceLastNudge += 1
            let decision = evaluateNudge(&record, state: &state, now: now, context: context)
            state.items[item.identity] = record
            state.log.append(LogEntry(at: now, kind: .menuUsed, identity: item.identity, bundleID: item.bundleID, phaseAfter: record.phase))
            return decision

        case .shortcutUsed:
            // Only a lesson in progress or a learned item has anything to count; ordinary
            // ⌘C traffic never touches the state file.
            guard record.phase == .coaching || record.phase == .learned else { return .ignore }
            record.shortcutUses.append(now)
            if record.shortcutUses.count > ItemRecord.maxShortcutUses {
                record.shortcutUses.removeFirst(record.shortcutUses.count - ItemRecord.maxShortcutUses)
            }
            if record.phase == .coaching {
                record.shortcutUsesSinceCoaching += 1
                if record.shortcutUsesSinceCoaching >= policy.learnAfter {
                    record.phase = .learned
                    record.learnedAt = now
                    record.menuUsesSinceLastNudge = 0
                }
            }
            state.items[item.identity] = record
            state.log.append(LogEntry(at: now, kind: .shortcutUsed, identity: item.identity, bundleID: item.bundleID, phaseAfter: record.phase))
            return .record
        }
    }

    /// Rules 1–9 of spec §6.2, in order. Mutates the record and the state only when it nudges.
    private func evaluateNudge(_ record: inout ItemRecord, state: inout CoachState, now: Date, context: CoachContext) -> CoachDecision {
        if context.isPaused || context.isAppPaused { return .record }
        if record.phase == .muted || record.isSnoozed(at: now) { return .record }

        let needed = threshold(for: record)
        guard record.menuUsesSinceLastNudge >= needed, record.menuUses.count >= needed else { return .record }

        if let last = record.lastNudgeAt, now.timeIntervalSince(last) < policy.itemSpacing { return .record }
        if let last = state.lastNudgeAt, now.timeIntervalSince(last) < policy.globalSpacing { return .record }
        let day = dayKey(now)
        if state.nudgesByDay[day, default: 0] >= policy.dailyCap { return .record }
        if context.isNudgeOnScreen || context.isOverlayVisible { return .record }

        if record.phase == .learned {
            record.regressions += 1
            record.learnedAt = nil
            record.shortcutUsesSinceCoaching = 0
        }
        record.phase = .coaching
        record.lastNudgeAt = now
        record.nudgeCount += 1
        record.menuUsesSinceLastNudge = 0
        state.lastNudgeAt = now
        state.nudgesByDay[day, default: 0] += 1
        return .nudge(record)
    }

    /// Menu uses an item needs before it may be nudged: the gentle cadence applies to
    /// learned items and to ones that have regressed before. A muted item never gets here.
    private func threshold(for record: ItemRecord) -> Int {
        switch record.phase {
        case .observed: return policy.nudgeAfter
        case .coaching: return record.regressions > 0 ? policy.regressAfter : policy.nudgeAfter
        case .learned, .muted: return policy.regressAfter
        }
    }

    // MARK: - User actions

    public func snooze(identity: String, until: Date, state: inout CoachState) {
        state.items[identity]?.snoozedUntil = until
    }

    public func clearSnooze(identity: String, state: inout CoachState) {
        state.items[identity]?.snoozedUntil = nil
    }

    public func mute(identity: String, state: inout CoachState) {
        state.items[identity]?.phase = .muted
    }

    public func unmute(identity: String, state: inout CoachState) {
        guard var record = state.items[identity], record.phase == .muted else { return }
        record.phase = .observed
        record.menuUsesSinceLastNudge = 0
        record.shortcutUsesSinceCoaching = 0
        record.lastNudgeAt = nil
        record.snoozedUntil = nil
        record.learnedAt = nil
        state.items[identity] = record
    }

    // MARK: - Housekeeping

    /// Drops what the policy no longer needs. Call on load and once a day. A coaching item
    /// with no use inside the window and no active snooze falls back to observed and is
    /// forgotten with the other empty records.
    public func prune(state: inout CoachState, now: Date) {
        let logCutoff = now.addingTimeInterval(-policy.logRetention)
        state.log.removeAll { $0.at < logCutoff }
        for (identity, original) in state.items {
            var record = original
            prune(&record, now: now)
            if record.phase == .coaching && record.menuUses.isEmpty && record.shortcutUses.isEmpty && !record.isSnoozed(at: now) {
                // A quiet window ends the lesson; the item starts over when it comes back.
                record.phase = .observed
                record.menuUsesSinceLastNudge = 0
                record.shortcutUsesSinceCoaching = 0
            }
            let forgettable = record.phase == .observed && record.menuUses.isEmpty && record.shortcutUses.isEmpty && record.snoozedUntil == nil
            state.items[identity] = forgettable ? nil : record
        }
        let dayCutoff = dayKey(logCutoff)
        state.nudgesByDay = state.nudgesByDay.filter { $0.key >= dayCutoff }
    }

    private func prune(_ record: inout ItemRecord, now: Date) {
        let cutoff = now.addingTimeInterval(-policy.window)
        record.menuUses.removeAll { $0 < cutoff }
        record.shortcutUses.removeAll { $0 < cutoff }
        if let until = record.snoozedUntil, until <= now { record.snoozedUntil = nil }
    }

    /// Local calendar day as "yyyy-MM-dd", always in the Gregorian calendar of
    /// `calendar`'s time zone, so string order equals date order whatever calendar the
    /// user prefers (Japanese era years would otherwise restart the numbering).
    public func dayKey(_ date: Date) -> String {
        let parts = dayCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

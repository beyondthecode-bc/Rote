import AppKit
import Foundation
import Observation
import OSLog
import RoteAX
import RoteCore

/// Wires Accessibility events into the coach and keeps the per-app menu cache (spec §4.3, §5.2, §6).
@MainActor
@Observable
final class CoachEngine {
    // MARK: Dependencies

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let scanner: any MenuScanning
    @ObservationIgnored private let tracker: FrontmostAppTracker
    @ObservationIgnored private let observer: MenuObserver
    @ObservationIgnored private let keyMonitor: KeyEventMonitor
    @ObservationIgnored private let store: StateStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isTrusted: @MainActor () -> Bool
    @ObservationIgnored private var coach: Coach
    @ObservationIgnored private let ownBundleID = Bundle.main.bundleIdentifier ?? "com.beyondthecode.rote"

    // MARK: Observable state

    private(set) var state = CoachState()
    private(set) var permissionGranted = false
    private(set) var currentApp: AppIdentity?
    private(set) var currentTree: MenuTree?
    private(set) var pauseUntil: Date?
    private(set) var recoveredCorruptFile: String?
    var nudgeOnScreen = false
    var overlayVisible = false

    // MARK: Callbacks

    @ObservationIgnored var onNudge: ((ItemRecord) -> Void)?
    @ObservationIgnored var onKeyEvent: ((KeyEventMonitor.Event) -> Void)?
    /// Every frontmost-app change the tracker reports: another app, Rote itself, or an app
    /// without a bundle ID.
    @ObservationIgnored var onAppActivated: (() -> Void)?

    // MARK: Internals

    @ObservationIgnored private var trees: [String: MenuTree] = [:]
    @ObservationIgnored private var treeOrder: [String] = []
    @ObservationIgnored private var scanTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var openMenuDepth = 0
    @ObservationIgnored private var lastMenuClosedAt: ContinuousClock.Instant?
    @ObservationIgnored private var echoes = ShortcutEchoFilter()
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var pauseExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var clockObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastPruneAt = Date.distantPast
    /// A selection this soon after a menu closed is still a pick from that menu.
    @ObservationIgnored private let menuCloseGrace: Duration
    /// Time between two prunes; the check runs on app activation.
    @ObservationIgnored private let pruneInterval: TimeInterval

    private static let treeCacheLimit = 20
    private static let treeStaleAfter: TimeInterval = 60
    static let pauseUntilKey = "coach.pauseUntil"

    init(
        settings: AppSettings,
        scanner: any MenuScanning = MenuScanner(),
        tracker: FrontmostAppTracker = FrontmostAppTracker(),
        observer: MenuObserver = MenuObserver(),
        keyMonitor: KeyEventMonitor = KeyEventMonitor(),
        store: StateStore = StateStore(fileURL: StateStore.defaultFileURL(), onWriteFailure: { error in
            Logger.engine.error("Could not save state: \(error.localizedDescription, privacy: .public)")
        }),
        defaults: UserDefaults = .standard,
        isTrusted: @escaping @MainActor () -> Bool = { AccessibilityPermission.isTrusted },
        menuCloseGrace: Duration = .milliseconds(300),
        pruneInterval: TimeInterval = 86_400
    ) {
        self.settings = settings
        self.scanner = scanner
        self.tracker = tracker
        self.observer = observer
        self.keyMonitor = keyMonitor
        self.store = store
        self.defaults = defaults
        self.isTrusted = isTrusted
        self.menuCloseGrace = menuCloseGrace
        self.pruneInterval = pruneInterval
        self.coach = Coach(policy: settings.policy, calendar: .autoupdatingCurrent)
    }

    var isPaused: Bool { pauseUntil.map { $0 > Date() } ?? false }
    /// "Pause until resumed" has no deadline: the popover shows "Paused" without a time.
    var isPausedUntilResumed: Bool { pauseUntil == .distantFuture }
    var isMenuOpen: Bool { openMenuDepth > 0 }

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        restorePause()
        switch await store.load() {
        case .fresh:
            break
        case .loaded(let loaded):
            state = loaded
        case .recovered(let name):
            recoveredCorruptFile = name
            Logger.engine.error("State file was unreadable; moved to \(name, privacy: .public)")
        }
        state.rekeyItems()
        coach.prune(state: &state, now: Date())
        lastPruneAt = Date()
        tracker.onActivate = { [weak self] app in self?.appActivated(app) }
        observer.onEvent = { [weak self] event in self?.handleObserverEvent(event) }
        keyMonitor.onEvent = { [weak self] event in self?.handleKeyEvent(event) }
        watchClock()
        startPermissionLoop()
    }

    func flush() async {
        await store.flush()
    }

    /// Call after any Settings change that affects `CoachPolicy`.
    func refreshPolicy() {
        coach = Coach(policy: settings.policy, calendar: .autoupdatingCurrent)
    }

    private func startPermissionLoop() {
        permissionTask?.cancel()
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let trusted = self.isTrusted()
                if trusted != self.permissionGranted { self.permissionChanged(trusted) }
                try? await Task.sleep(for: .seconds(trusted ? 5 : 1))
            }
        }
    }

    private func permissionChanged(_ granted: Bool) {
        permissionGranted = granted
        Logger.engine.info("Accessibility trusted: \(granted)")
        if granted {
            tracker.start()
            keyMonitor.start()
        } else {
            observer.detach()
            tracker.stop()
            keyMonitor.stop()
            currentApp = nil
            currentTree = nil
        }
    }

    /// A pause deadline is wall-clock time: one crossed during sleep or by a clock change ends at once.
    private func watchClock() {
        let recheck: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.schedulePauseExpiry() }
        }
        clockObservers = [
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: recheck),
            NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: recheck),
        ]
    }

    // MARK: App activation and tree cache

    private func appActivated(_ app: AppIdentity?) {
        onAppActivated?()
        openMenuDepth = 0
        echoes.reset()
        guard let app else {
            // An app without a bundle ID is frontmost: stop coaching the previous app (spec §4.3).
            observer.detach()
            currentApp = nil
            currentTree = nil
            return
        }
        guard app.bundleID != ownBundleID else {
            // Rote itself is frontmost (onboarding, Settings). With the observer detached and its own
            // presses never matched nothing is coached, but a sheet opened from here keeps the app
            // the user came from (spec §7.5).
            observer.detach()
            return
        }
        currentApp = app
        if Date().timeIntervalSince(lastPruneAt) > pruneInterval {
            coach.prune(state: &state, now: Date())
            lastPruneAt = Date()
            persist()
        }
        do {
            try observer.attach(app)
        } catch {
            Logger.ax.error("Could not observe \(app.bundleID, privacy: .private): \(String(describing: error), privacy: .public)")
        }
        ensureTree(for: app)
    }

    private func ensureTree(for app: AppIdentity) {
        if let tree = trees[app.bundleID] {
            currentTree = tree
            touch(app.bundleID)
            let fresh = Date().timeIntervalSince(tree.scannedAt) < Self.treeStaleAfter && !tree.isPartial
            if fresh { return }
        } else {
            currentTree = nil
        }
        scan(app)
    }

    private func scan(_ app: AppIdentity) {
        guard scanTasks[app.bundleID] == nil else { return }
        let scanner = self.scanner
        scanTasks[app.bundleID] = Task { [weak self] in
            let started = Date()
            let scanned = await scanner.scan(app: app)
            guard let self else { return }
            self.scanTasks[app.bundleID] = nil
            let tree = scanned.merged(over: self.trees[app.bundleID])
            self.trees[app.bundleID] = tree
            self.touch(app.bundleID)
            if self.currentApp?.bundleID == app.bundleID { self.currentTree = tree }
            // Bundle IDs are public at debug level only; they name the apps the user runs (audit M2).
            Logger.ax.debug("Scanned \(app.bundleID, privacy: .public): \(tree.shortcutCount) shortcuts in \(Int(Date().timeIntervalSince(started) * 1000)) ms, partial=\(tree.isPartial)")
        }
    }

    private func touch(_ bundleID: String) {
        treeOrder.removeAll { $0 == bundleID }
        treeOrder.append(bundleID)
        while treeOrder.count > Self.treeCacheLimit {
            trees[treeOrder.removeFirst()] = nil
        }
    }

    // MARK: Events

    private func handleObserverEvent(_ event: MenuObserverEvent) {
        switch event {
        case .menuOpened:
            openMenuDepth += 1
            echoes.reset()
        case .menuClosed:
            openMenuDepth = max(0, openMenuDepth - 1)
            lastMenuClosedAt = .now
        case .itemSelected(let record):
            let now = Date()
            let tick = ContinuousClock.now
            // AppKit also reports a key equivalent as a selection once its action returns; the
            // key monitor has counted that press already (spec §5.5).
            if !echoes.isEcho(record, at: tick) {
                let viaMenu = openMenuDepth > 0 || lastMenuClosedAt.map { $0.duration(to: tick) < menuCloseGrace } ?? false
                if viaMenu {
                    process(CoachEvent(kind: .menuUsed, item: record, at: now))
                } else {
                    echoes.selectionCounted(record, at: tick)
                    process(CoachEvent(kind: .shortcutUsed, item: record, at: now))
                }
            }
            if let tree = currentTree, !tree.contains(identity: record.identity), let app = currentApp {
                scan(app)
            }
        }
    }

    private func handleKeyEvent(_ event: KeyEventMonitor.Event) {
        onKeyEvent?(event)
        guard case .keyDown(let press, inOwnApp: false) = event, let tree = currentTree else { return }
        guard let item = tree.item(for: press) else { return }   // nil for auto-repeats
        guard echoes.keyPressMatched(item, at: .now) else { return }   // its selection came first and counted
        process(CoachEvent(kind: .shortcutUsed, item: item, at: Date()))
    }

    private func process(_ event: CoachEvent) {
        let context = CoachContext(
            isPaused: isPaused,
            isAppExcluded: settings.excludedBundleIDs.contains(event.item.bundleID),
            isAppPaused: settings.pausedBundleIDs.contains(event.item.bundleID),
            isNudgeOnScreen: nudgeOnScreen,
            isOverlayVisible: overlayVisible,
            ownBundleID: ownBundleID
        )
        // Assigned only when the coach changed it: an ignored ⌘C must not invalidate every view of `state`.
        var next = state
        let decision = coach.handle(event, state: &next, context: context)
        if decision != .ignore { state = next }
        switch decision {
        case .nudge(let record):
            nudgeOnScreen = true
            // A title can carry a document, volume or mailbox name; the unified log is readable by
            // every admin and collected by sysdiagnose, so the title is private (audit M2).
            Logger.engine.info("Nudge: \(record.item.title, privacy: .private)")
            onNudge?(record)
            persist()
        case .record:
            persist()
        case .ignore:
            break
        }
    }

    private func persist() {
        let snapshot = state
        Task { await store.scheduleSave(snapshot) }
    }

    // MARK: Actions from the UI

    func nudgeDismissed() { nudgeOnScreen = false }

    /// The corrupt-file notice is one-time: the popover's OK clears it (spec §10).
    func acknowledgeRecoveryNotice() { recoveredCorruptFile = nil }

    func snooze(_ identity: String, days: Int = 7) {
        coach.snooze(identity: identity, until: Date().addingTimeInterval(Double(days) * 86_400), state: &state)
        persist()
    }

    func mute(_ identity: String) {
        coach.mute(identity: identity, state: &state)
        persist()
    }

    func unmute(_ identity: String) {
        coach.unmute(identity: identity, state: &state)
        persist()
    }

    func pause(for interval: TimeInterval) { pause(until: Date().addingTimeInterval(interval)) }

    func pauseUntilTomorrow() {
        let start = Calendar.current.startOfDay(for: Date())
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        pause(until: tomorrow)
    }

    func pauseUntilResumed() { pause(until: .distantFuture) }

    func resume() {
        pauseExpiryTask?.cancel()
        pauseExpiryTask = nil
        setPauseUntil(nil)
    }

    private func pause(until deadline: Date) {
        setPauseUntil(deadline)
        schedulePauseExpiry()
    }

    /// The deadline is kept in UserDefaults too, so a relaunch never silently drops a pause.
    private func setPauseUntil(_ deadline: Date?) {
        pauseUntil = deadline
        if let deadline {
            defaults.set(deadline, forKey: Self.pauseUntilKey)
        } else {
            defaults.removeObject(forKey: Self.pauseUntilKey)
        }
    }

    /// Restores the pause an earlier run saved, unless its deadline has passed.
    private func restorePause() {
        guard let saved = defaults.object(forKey: Self.pauseUntilKey) as? Date else { return }
        if saved > Date() {
            pause(until: saved)
        } else {
            defaults.removeObject(forKey: Self.pauseUntilKey)
        }
    }

    /// Clears `pauseUntil` once it passes, so the menu bar icon and the popover, which observe it,
    /// show coaching back on (spec §6.3). The wait is monotonic and the deadline is wall-clock, so
    /// it re-checks after the wait, on wake and on a clock change. A pause until resumed has no
    /// deadline to wait for.
    private func schedulePauseExpiry() {
        pauseExpiryTask?.cancel()
        pauseExpiryTask = nil
        guard let deadline = pauseUntil, !isPausedUntilResumed else { return }
        pauseExpiryTask = Task { [weak self] in
            while deadline.timeIntervalSinceNow > 0 {
                try? await Task.sleep(for: .seconds(deadline.timeIntervalSinceNow))
                if Task.isCancelled { return }
            }
            guard !Task.isCancelled, let self, self.pauseUntil == deadline else { return }
            self.setPauseUntil(nil)
            self.pauseExpiryTask = nil
        }
    }

    func resetStatistics() {
        coach.resetStatistics(state: &state)
        persist()
    }

    func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(state)
    }

    // MARK: Derived lists

    var weeklyStats: WeeklyStats { Stats.weekly(state: state, now: Date(), calendar: .current) }
    var coachingNow: [ItemRecord] { Stats.coachingNow(state: state, now: Date()) }
    var learnedRecently: [ItemRecord] { Stats.learned(state: state, limit: 10) }
    var learnedTotal: Int { Stats.learnedCount(state: state) }
    var mutedItems: [ItemRecord] { Stats.muted(state: state) }

    #if DEBUG
    /// Feeds a fake event through the real pipeline, for screenshots and manual testing.
    func simulate(_ event: CoachEvent) { process(event) }

    /// Forgets one item, the last nudge and today's nudge count, so an earlier simulated nudge,
    /// snooze or mute cannot hold the next one back.
    func debugForget(_ identity: String) {
        state.items[identity] = nil
        state.lastNudgeAt = nil
        state.nudgesByDay[coach.dayKey(Date())] = nil
    }
    #endif
}

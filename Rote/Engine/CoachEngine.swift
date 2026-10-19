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

    // MARK: Internals

    @ObservationIgnored private var trees: [String: MenuTree] = [:]
    @ObservationIgnored private var treeOrder: [String] = []
    @ObservationIgnored private var scanTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var openMenuDepth = 0
    @ObservationIgnored private var lastMenuClosedAt = Date.distantPast
    @ObservationIgnored private var lastShortcutUse: (identity: String, at: Date)?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastPruneAt = Date.distantPast

    private static let treeCacheLimit = 20
    private static let pruneInterval: TimeInterval = 86_400
    private static let treeStaleAfter: TimeInterval = 60
    private static let menuCloseGrace: TimeInterval = 0.3
    private static let duplicateWindow: TimeInterval = 0.3

    init(
        settings: AppSettings,
        scanner: any MenuScanning = MenuScanner(),
        tracker: FrontmostAppTracker = FrontmostAppTracker(),
        observer: MenuObserver = MenuObserver(),
        keyMonitor: KeyEventMonitor = KeyEventMonitor(),
        store: StateStore = StateStore(fileURL: StateStore.defaultFileURL(), onWriteFailure: { error in
            Logger.engine.error("Could not save state: \(error.localizedDescription, privacy: .public)")
        })
    ) {
        self.settings = settings
        self.scanner = scanner
        self.tracker = tracker
        self.observer = observer
        self.keyMonitor = keyMonitor
        self.store = store
        self.coach = Coach(policy: settings.policy, calendar: .autoupdatingCurrent)
    }

    var isPaused: Bool { pauseUntil.map { $0 > Date() } ?? false }
    var isMenuOpen: Bool { openMenuDepth > 0 }

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true
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
                let trusted = AccessibilityPermission.isTrusted
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

    // MARK: App activation and tree cache

    private func appActivated(_ app: AppIdentity?) {
        guard let app, app.bundleID != ownBundleID else {
            // An app without a bundle ID, or Rote itself, is frontmost: stop coaching the previous app (spec §4.3).
            observer.detach()
            currentApp = nil
            currentTree = nil
            openMenuDepth = 0
            return
        }
        currentApp = app
        openMenuDepth = 0
        if Date().timeIntervalSince(lastPruneAt) > Self.pruneInterval {
            coach.prune(state: &state, now: Date())
            lastPruneAt = Date()
            persist()
        }
        do {
            try observer.attach(app)
        } catch {
            Logger.ax.error("Could not observe \(app.bundleID, privacy: .public): \(String(describing: error), privacy: .public)")
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
            Logger.ax.info("Scanned \(app.bundleID, privacy: .public): \(tree.shortcutCount) shortcuts in \(Int(Date().timeIntervalSince(started) * 1000)) ms, partial=\(tree.isPartial)")
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
        case .menuClosed:
            openMenuDepth = max(0, openMenuDepth - 1)
            lastMenuClosedAt = Date()
        case .itemSelected(let record):
            let now = Date()
            let viaMenu = openMenuDepth > 0 || now.timeIntervalSince(lastMenuClosedAt) < Self.menuCloseGrace
            if viaMenu {
                process(CoachEvent(kind: .menuUsed, item: record, at: now))
            } else {
                shortcutUsed(record, at: now)
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
        shortcutUsed(item, at: Date())
    }

    private func shortcutUsed(_ item: MenuItemRecord, at now: Date) {
        if let last = lastShortcutUse, last.identity == item.identity, now.timeIntervalSince(last.at) < Self.duplicateWindow { return }
        lastShortcutUse = (item.identity, now)
        process(CoachEvent(kind: .shortcutUsed, item: item, at: now))
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
        switch coach.handle(event, state: &state, context: context) {
        case .nudge(let record):
            nudgeOnScreen = true
            Logger.engine.info("Nudge: \(record.item.title, privacy: .public)")
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

    func pause(for interval: TimeInterval) { pauseUntil = Date().addingTimeInterval(interval) }

    func pauseUntilTomorrow() {
        let start = Calendar.current.startOfDay(for: Date())
        pauseUntil = Calendar.current.date(byAdding: .day, value: 1, to: start)
    }

    func resume() { pauseUntil = nil }

    func resetStatistics() {
        state = CoachState()
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
    #endif
}

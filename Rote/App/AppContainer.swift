import AppKit
import Foundation
import Observation
import OSLog
import RoteAX
import RoteCore

/// Composition root. One instance for the whole process.
@MainActor
@Observable
final class AppContainer {
    static let shared = AppContainer()

    let settings: AppSettings
    let engine: CoachEngine
    let nudges: NudgeController
    let overlay: OverlayController

    var updateAvailable: (version: String, url: URL)?
    @ObservationIgnored private var started = false

    private init() {
        settings = AppSettings()
        engine = CoachEngine(settings: settings)
        nudges = NudgeController(settings: settings)
        overlay = OverlayController(settings: settings, engine: engine)
        wire()
    }

    func start() {
        guard !started else { return }
        started = true
        Task { await engine.start() }
        if settings.checkUpdatesOnLaunch {
            Task { await checkForUpdates() }
        }
    }

    var iconState: MenuBarIcon.State {
        if !engine.permissionGranted { return .needsPermission }
        if engine.isPaused { return .paused }
        return .normal
    }

    private func wire() {
        engine.onNudge = { [weak self] record in self?.presentNudge(record) }
        nudges.onDismiss = { [weak self] in self?.engine.nudgeDismissed() }
        nudges.onSnooze = { [weak self] identity in self?.engine.snooze(identity) }
        nudges.onMute = { [weak self] identity in self?.engine.mute(identity) }
        nudges.onPauseHour = { [weak self] in self?.engine.pause(for: 3_600) }
        engine.onKeyEvent = { [weak self] event in self?.overlay.handle(event) }
    }

    func presentNudge(_ record: ItemRecord) {
        let info = AppInfo.resolve(record.item.bundleID)
        nudges.show(record, appName: info.name, appIcon: info.icon)
    }

    private func checkForUpdates() async {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        do {
            if case .available(let newVersion, let url) = try await GitHubUpdateChecker.checkForUpdate(currentVersion: version) {
                updateAvailable = (newVersion, url)
            }
        } catch {
            Logger.updater.info("Update check skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    #if DEBUG
    /// Three fake mouse uses of Safari › View › Reload Page, through the real coach. The item's
    /// history is forgotten first, so every run nudges unless a pause, an exclusion or a HUD on screen stops it.
    func simulateNudge() {
        let item = MenuItemRecord(bundleID: "com.apple.Safari", path: ["View", "Reload Page"], shortcut: Shortcut(modifiers: [.command], key: .character("R")))
        engine.debugForget(item.identity)
        let now = Date()
        for offset in [-120.0, -60.0, 0.0] {
            engine.simulate(CoachEvent(kind: .menuUsed, item: item, at: now.addingTimeInterval(offset)))
        }
    }

    /// Writes the current app's raw menu snapshot to the Desktop, for test fixtures.
    func exportSnapshot() {
        guard let app = engine.currentApp else { return }
        Task {
            let snapshot = await MenuScanner(budget: 5).snapshot(app: app)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop/rote-snapshot-\(app.bundleID).json")
            do {
                try encoder.encode(snapshot).write(to: url)
                Logger.engine.info("Snapshot written to \(url.path, privacy: .public)")
            } catch {
                Logger.engine.error("Snapshot failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    #endif
}

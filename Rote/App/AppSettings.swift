import Foundation
import Observation
import RoteCore

/// User-facing settings (spec §7.4), persisted in UserDefaults, mirrored into `CoachPolicy`.
@MainActor
@Observable
final class AppSettings {
    enum OverlayTrigger: String, CaseIterable {
        case holdCommand, holdOption, stickyHotkey
    }

    enum Keys {
        static let nudgeAfter = "coach.nudgeAfter"
        static let itemSpacingHours = "coach.itemSpacingHours"
        static let dailyCap = "coach.dailyCap"
        static let hudDuration = "coach.hudDuration"
        static let soundEnabled = "coach.soundEnabled"
        static let overlayTrigger = "overlay.trigger"
        static let holdDelayMs = "overlay.holdDelayMs"
        static let showItemsWithoutShortcuts = "overlay.showItemsWithoutShortcuts"
        static let showAppleMenu = "overlay.showAppleMenu"
        static let excludedBundleIDs = "apps.excluded"
        static let pausedBundleIDs = "apps.paused"
        static let checkUpdatesOnLaunch = "updates.checkOnLaunch"
        static let hasCompletedOnboarding = "onboarding.completed"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isLoading = true

    var nudgeAfter: Int = 3 { didSet { save(nudgeAfter, Keys.nudgeAfter) } }
    var itemSpacingHours: Int = 4 { didSet { save(itemSpacingHours, Keys.itemSpacingHours) } }
    var dailyCap: Int = 12 { didSet { save(dailyCap, Keys.dailyCap) } }
    var hudDuration: Double = 2.5 { didSet { save(hudDuration, Keys.hudDuration) } }
    var soundEnabled: Bool = false { didSet { save(soundEnabled, Keys.soundEnabled) } }
    var overlayTrigger: OverlayTrigger = .holdCommand { didSet { save(overlayTrigger.rawValue, Keys.overlayTrigger) } }
    var holdDelayMs: Int = 700 { didSet { save(holdDelayMs, Keys.holdDelayMs) } }
    var showItemsWithoutShortcuts: Bool = false { didSet { save(showItemsWithoutShortcuts, Keys.showItemsWithoutShortcuts) } }
    var showAppleMenu: Bool = false { didSet { save(showAppleMenu, Keys.showAppleMenu) } }
    var excludedBundleIDs: [String] = [] { didSet { save(excludedBundleIDs, Keys.excludedBundleIDs) } }
    var pausedBundleIDs: [String] = [] { didSet { save(pausedBundleIDs, Keys.pausedBundleIDs) } }
    var checkUpdatesOnLaunch: Bool = true { didSet { save(checkUpdatesOnLaunch, Keys.checkUpdatesOnLaunch) } }
    var hasCompletedOnboarding: Bool = false { didSet { save(hasCompletedOnboarding, Keys.hasCompletedOnboarding) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        isLoading = false
    }

    var policy: CoachPolicy {
        CoachPolicy(nudgeAfter: nudgeAfter, itemSpacing: Double(itemSpacingHours) * 3_600, dailyCap: dailyCap)
    }

    private func load() {
        if let v = defaults.object(forKey: Keys.nudgeAfter) as? Int { nudgeAfter = v }
        if let v = defaults.object(forKey: Keys.itemSpacingHours) as? Int { itemSpacingHours = v }
        if let v = defaults.object(forKey: Keys.dailyCap) as? Int { dailyCap = v }
        if let v = defaults.object(forKey: Keys.hudDuration) as? Double { hudDuration = v }
        if let v = defaults.object(forKey: Keys.soundEnabled) as? Bool { soundEnabled = v }
        if let raw = defaults.string(forKey: Keys.overlayTrigger), let v = OverlayTrigger(rawValue: raw) { overlayTrigger = v }
        if let v = defaults.object(forKey: Keys.holdDelayMs) as? Int { holdDelayMs = v }
        if let v = defaults.object(forKey: Keys.showItemsWithoutShortcuts) as? Bool { showItemsWithoutShortcuts = v }
        if let v = defaults.object(forKey: Keys.showAppleMenu) as? Bool { showAppleMenu = v }
        if let v = defaults.array(forKey: Keys.excludedBundleIDs) as? [String] { excludedBundleIDs = v }
        if let v = defaults.array(forKey: Keys.pausedBundleIDs) as? [String] { pausedBundleIDs = v }
        if let v = defaults.object(forKey: Keys.checkUpdatesOnLaunch) as? Bool { checkUpdatesOnLaunch = v }
        if let v = defaults.object(forKey: Keys.hasCompletedOnboarding) as? Bool { hasCompletedOnboarding = v }
    }

    private func save(_ value: Any, _ key: String) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
    }
}

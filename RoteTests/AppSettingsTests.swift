import XCTest
@testable import Rote
import RoteCore

/// Loading from and saving to a throwaway defaults suite.
@MainActor
final class AppSettingsTests: XCTestCase {
    private typealias Keys = AppSettings.Keys

    private func makeDefaults() -> TestDefaults {
        let testDefaults = TestDefaults()
        addTeardownBlock { testDefaults.remove() }
        return testDefaults
    }

    func testAnEmptyStoreGivesTheDefaultsAndWritesNothing() {
        let store = makeDefaults()
        let settings = AppSettings(defaults: store.defaults)

        XCTAssertEqual(settings.nudgeAfter, 3)
        XCTAssertEqual(settings.itemSpacingHours, 4)
        XCTAssertEqual(settings.dailyCap, 12)
        XCTAssertEqual(settings.hudDuration, 2.5)
        XCTAssertFalse(settings.soundEnabled)
        XCTAssertEqual(settings.overlayTrigger, .holdCommand)
        XCTAssertEqual(settings.holdDelayMs, 700)
        XCTAssertFalse(settings.showItemsWithoutShortcuts)
        XCTAssertFalse(settings.showAppleMenu)
        XCTAssertEqual(settings.excludedBundleIDs, [])
        XCTAssertEqual(settings.pausedBundleIDs, [])
        XCTAssertTrue(settings.checkUpdatesOnLaunch)
        XCTAssertFalse(settings.hasCompletedOnboarding)
        XCTAssertTrue(store.defaults.persistentDomain(forName: store.name)?.isEmpty ?? true)
    }

    func testValuesBelowTheirRangeAreRaisedToTheMinimum() {
        let store = makeDefaults()
        store.defaults.set(0, forKey: Keys.nudgeAfter)
        store.defaults.set(0, forKey: Keys.itemSpacingHours)
        store.defaults.set(1, forKey: Keys.dailyCap)
        store.defaults.set(0.2, forKey: Keys.hudDuration)
        store.defaults.set(50, forKey: Keys.holdDelayMs)

        let settings = AppSettings(defaults: store.defaults)

        XCTAssertEqual(settings.nudgeAfter, 2)
        XCTAssertEqual(settings.itemSpacingHours, 1)
        XCTAssertEqual(settings.dailyCap, 3)
        XCTAssertEqual(settings.hudDuration, 1.5)
        XCTAssertEqual(settings.holdDelayMs, 400)
    }

    func testValuesAboveTheirRangeAreLoweredToTheMaximum() {
        let store = makeDefaults()
        store.defaults.set(99, forKey: Keys.nudgeAfter)
        store.defaults.set(99, forKey: Keys.itemSpacingHours)
        store.defaults.set(999, forKey: Keys.dailyCap)
        store.defaults.set(60.0, forKey: Keys.hudDuration)
        store.defaults.set(9_000, forKey: Keys.holdDelayMs)

        let settings = AppSettings(defaults: store.defaults)

        XCTAssertEqual(settings.nudgeAfter, 5)
        XCTAssertEqual(settings.itemSpacingHours, 24)
        XCTAssertEqual(settings.dailyCap, 30)
        XCTAssertEqual(settings.hudDuration, 5.0)
        XCTAssertEqual(settings.holdDelayMs, 1_500)
    }

    func testValuesInsideTheirRangeIncludingTheBoundsAreKept() {
        for (nudge, spacing, cap, duration, delay) in [(2, 1, 3, 1.5, 400), (4, 6, 20, 3.5, 900), (5, 24, 30, 5.0, 1_500)] {
            let store = makeDefaults()
            store.defaults.set(nudge, forKey: Keys.nudgeAfter)
            store.defaults.set(spacing, forKey: Keys.itemSpacingHours)
            store.defaults.set(cap, forKey: Keys.dailyCap)
            store.defaults.set(duration, forKey: Keys.hudDuration)
            store.defaults.set(delay, forKey: Keys.holdDelayMs)

            let settings = AppSettings(defaults: store.defaults)

            XCTAssertEqual(settings.nudgeAfter, nudge)
            XCTAssertEqual(settings.itemSpacingHours, spacing)
            XCTAssertEqual(settings.dailyCap, cap)
            XCTAssertEqual(settings.hudDuration, duration)
            XCTAssertEqual(settings.holdDelayMs, delay)
        }
    }

    func testEveryOtherStoredValueIsLoaded() {
        let store = makeDefaults()
        store.defaults.set(true, forKey: Keys.soundEnabled)
        store.defaults.set("stickyHotkey", forKey: Keys.overlayTrigger)
        store.defaults.set(true, forKey: Keys.showItemsWithoutShortcuts)
        store.defaults.set(true, forKey: Keys.showAppleMenu)
        store.defaults.set(["com.example.Alpha"], forKey: Keys.excludedBundleIDs)
        store.defaults.set(["com.example.Beta"], forKey: Keys.pausedBundleIDs)
        store.defaults.set(false, forKey: Keys.checkUpdatesOnLaunch)
        store.defaults.set(true, forKey: Keys.hasCompletedOnboarding)

        let settings = AppSettings(defaults: store.defaults)

        XCTAssertTrue(settings.soundEnabled)
        XCTAssertEqual(settings.overlayTrigger, .stickyHotkey)
        XCTAssertTrue(settings.showItemsWithoutShortcuts)
        XCTAssertTrue(settings.showAppleMenu)
        XCTAssertEqual(settings.excludedBundleIDs, ["com.example.Alpha"])
        XCTAssertEqual(settings.pausedBundleIDs, ["com.example.Beta"])
        XCTAssertFalse(settings.checkUpdatesOnLaunch)
        XCTAssertTrue(settings.hasCompletedOnboarding)
    }

    func testClampingOnLoadLeavesTheStoredValueAlone() {
        let store = makeDefaults()
        store.defaults.set(99, forKey: Keys.nudgeAfter)

        let settings = AppSettings(defaults: store.defaults)

        XCTAssertEqual(settings.nudgeAfter, 5)
        XCTAssertEqual(store.defaults.integer(forKey: Keys.nudgeAfter), 99)
    }

    func testANonFiniteDisplayTimeIsIgnored() {
        for value in [Double.infinity, -Double.infinity, Double.nan] {
            let store = makeDefaults()
            store.defaults.set(value, forKey: Keys.hudDuration)
            XCTAssertNotNil(store.defaults.object(forKey: Keys.hudDuration) as? Double)

            XCTAssertEqual(AppSettings(defaults: store.defaults).hudDuration, 2.5)
        }
    }

    func testValuesOfTheWrongTypeAreIgnored() {
        let store = makeDefaults()
        store.defaults.set("4", forKey: Keys.nudgeAfter)
        store.defaults.set("yes", forKey: Keys.soundEnabled)
        store.defaults.set("holdShift", forKey: Keys.overlayTrigger)
        store.defaults.set("com.example.Alpha", forKey: Keys.excludedBundleIDs)
        store.defaults.set([1, 2], forKey: Keys.pausedBundleIDs)

        let settings = AppSettings(defaults: store.defaults)

        XCTAssertEqual(settings.nudgeAfter, 3)
        XCTAssertFalse(settings.soundEnabled)
        XCTAssertEqual(settings.overlayTrigger, .holdCommand)
        XCTAssertEqual(settings.excludedBundleIDs, [])
        XCTAssertEqual(settings.pausedBundleIDs, [])
    }

    func testChangesAreSavedAndReadBack() {
        let store = makeDefaults()
        let settings = AppSettings(defaults: store.defaults)

        settings.nudgeAfter = 4
        settings.itemSpacingHours = 6
        settings.dailyCap = 20
        settings.hudDuration = 3.5
        settings.soundEnabled = true
        settings.overlayTrigger = .holdOption
        settings.holdDelayMs = 900
        settings.showItemsWithoutShortcuts = true
        settings.showAppleMenu = true
        settings.excludedBundleIDs = ["com.example.Alpha"]
        settings.pausedBundleIDs = ["com.example.Beta"]
        settings.checkUpdatesOnLaunch = false
        settings.hasCompletedOnboarding = true

        XCTAssertEqual(store.defaults.object(forKey: Keys.nudgeAfter) as? Int, 4)
        XCTAssertEqual(store.defaults.object(forKey: Keys.hudDuration) as? Double, 3.5)
        XCTAssertEqual(store.defaults.string(forKey: Keys.overlayTrigger), "holdOption")
        XCTAssertEqual(store.defaults.stringArray(forKey: Keys.excludedBundleIDs), ["com.example.Alpha"])

        let reloaded = AppSettings(defaults: store.defaults)
        XCTAssertEqual(reloaded.nudgeAfter, 4)
        XCTAssertEqual(reloaded.itemSpacingHours, 6)
        XCTAssertEqual(reloaded.dailyCap, 20)
        XCTAssertEqual(reloaded.hudDuration, 3.5)
        XCTAssertTrue(reloaded.soundEnabled)
        XCTAssertEqual(reloaded.overlayTrigger, .holdOption)
        XCTAssertEqual(reloaded.holdDelayMs, 900)
        XCTAssertTrue(reloaded.showItemsWithoutShortcuts)
        XCTAssertTrue(reloaded.showAppleMenu)
        XCTAssertEqual(reloaded.excludedBundleIDs, ["com.example.Alpha"])
        XCTAssertEqual(reloaded.pausedBundleIDs, ["com.example.Beta"])
        XCTAssertFalse(reloaded.checkUpdatesOnLaunch)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
    }

    func testThePolicyMirrorsTheCoachingSettings() {
        let store = makeDefaults()
        let settings = AppSettings(defaults: store.defaults)
        settings.nudgeAfter = 4
        settings.itemSpacingHours = 6
        settings.dailyCap = 20

        XCTAssertEqual(settings.policy, CoachPolicy(nudgeAfter: 4, itemSpacing: 21_600, dailyCap: 20))
    }
}

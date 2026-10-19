import XCTest
@testable import Rote

/// Onboarding step 3's wording, from the shipped string tables with the language pinned per test.
@MainActor
final class OnboardingTryItTests: XCTestCase {
    private func strings(_ code: String) -> LocalizationManager {
        let testDefaults = TestDefaults()
        addTeardownBlock { testDefaults.remove() }
        testDefaults.defaults.set(code, forKey: "rote.language")
        return LocalizationManager(defaults: testDefaults.defaults, bundle: .main)
    }

    private func text(_ trigger: AppSettings.OverlayTrigger, granted: Bool = true, _ strings: LocalizationManager) -> String {
        OnboardingView.tryItText(trigger: trigger, accessGranted: granted, strings: strings)
    }

    func testStepThreeSendsTheUserToAnotherAppAndNamesTheChosenTrigger() {
        let english = strings("en")
        XCTAssertEqual(text(.holdCommand, english), "Switch to another app, for example Finder, then hold ⌘ for a moment to see every shortcut it has.")
        XCTAssertEqual(text(.holdOption, english), "Switch to another app, for example Finder, then hold ⌥ for a moment to see every shortcut it has.")
        XCTAssertEqual(text(.stickyHotkey, english), "Switch to another app, for example Finder, then press ⌃⌥⌘K to see every shortcut it has.")
    }

    func testWithoutAccessStepThreeSaysTheDemoNeedsItFirst() {
        let english = strings("en")
        for trigger in AppSettings.OverlayTrigger.allCases {
            XCTAssertEqual(
                text(trigger, granted: false, english),
                "The demo needs Accessibility access first. Turn on Rote under Privacy & Security › Accessibility, and the demo appears here.",
                "\(trigger)"
            )
        }
    }

    func testEveryLanguageNamesEachTriggerInStepThree() {
        let expected: [(AppSettings.OverlayTrigger, String, [String])] = [
            (.holdCommand, "⌘", ["⌥", "⌃"]),
            (.holdOption, "⌥", ["⌘", "⌃"]),
            (.stickyHotkey, "⌃⌥⌘K", []),
        ]
        for code in LocalizationManager.supportedCodes {
            let strings = strings(code)
            let blocked = text(.holdCommand, granted: false, strings)
            XCTAssertTrue(blocked.contains("Rote"), "\(code): \(blocked)")
            XCTAssertFalse(blocked.contains("onboarding."), "\(code): \(blocked)")
            for (trigger, keys, absent) in expected {
                let wording = text(trigger, strings)
                XCTAssertTrue(wording.contains(keys), "\(code) \(trigger): \(wording)")
                for other in absent { XCTAssertFalse(wording.contains(other), "\(code) \(trigger): \(wording)") }
                XCTAssertFalse(wording.contains("%"), "\(code) \(trigger): \(wording)")
                XCTAssertFalse(wording.contains("onboarding."), "\(code) \(trigger): \(wording)")
                XCTAssertNotEqual(wording, blocked, "\(code) \(trigger)")
            }
        }
    }
}

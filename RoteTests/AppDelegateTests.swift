import AppKit
import XCTest
@testable import Rote

@MainActor
final class AppDelegateTests: XCTestCase {
    func testAnXCTestHostIsRecognisedByItsConfigurationVariable() {
        XCTAssertTrue(AppDelegate.isTestHost(environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]))
        XCTAssertFalse(AppDelegate.isTestHost(environment: [:]))
        XCTAssertFalse(AppDelegate.isTestHost(environment: ["XCTestBundlePath": "/tmp/x.xctest"]))
    }

    func testThisProcessIsTheTestHost() {
        XCTAssertTrue(AppDelegate.isTestHost())
    }

    /// Launch has finished before any test runs; a started container would mean the real engine,
    /// the user's state file and the update check are live under test.
    func testTheHostAppDidNotStartTheContainer() {
        XCTAssertFalse(AppContainer.shared.started)
    }

    /// The test host has no menu bar extra at all, so a test run puts no item in the menu bar. Not
    /// even a hidden one: a hidden status item saves its visibility in the app's own defaults.
    func testTheTestHostHasNoStatusItem() {
        let statusItems = NSApp.windows.filter { NSStringFromClass(type(of: $0)).contains("StatusBar") }
        XCTAssertEqual(statusItems.map { NSStringFromClass(type(of: $0)) }, [])
    }
}

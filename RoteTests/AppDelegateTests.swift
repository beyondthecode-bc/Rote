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
}

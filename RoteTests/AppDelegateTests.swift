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
}

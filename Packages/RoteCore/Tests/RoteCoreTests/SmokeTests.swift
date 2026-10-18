import XCTest
@testable import RoteCore

final class SmokeTests: XCTestCase {
    func testPackageLinks() {
        XCTAssertEqual(RoteCoreInfo.schemaVersion, 1)
    }
}

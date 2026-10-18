import XCTest
@testable import RoteAX

final class SmokeTests: XCTestCase {
    func testPackageLinks() {
        XCTAssertEqual(RoteAXInfo.coreSchemaVersion, 1)
    }
}

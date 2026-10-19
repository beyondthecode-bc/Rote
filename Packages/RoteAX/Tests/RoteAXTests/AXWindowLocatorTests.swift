import CoreGraphics
import XCTest
@testable import RoteAX

final class AXWindowLocatorTests: XCTestCase {
    private let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let above = CGRect(x: 0, y: 982, width: 2560, height: 1440)
    private let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)

    func testWindowOnThePrimaryDisplayFlipsAboutItsHeight() {
        let frame = AXWindowLocator.appKitFrame(position: CGPoint(x: 0, y: 33), size: CGSize(width: 1512, height: 871), primaryScreenFrame: primary)
        XCTAssertEqual(frame, CGRect(x: 0, y: 78, width: 1512, height: 871))
        XCTAssertEqual(AXWindowLocator.index(ofFrameContaining: frame, in: [primary, above, left]), 0)
    }

    /// A display above the primary has negative Accessibility y.
    func testWindowOnADisplayAboveThePrimary() {
        let frame = AXWindowLocator.appKitFrame(position: CGPoint(x: 100, y: -1000), size: CGSize(width: 800, height: 600), primaryScreenFrame: primary)
        XCTAssertEqual(frame, CGRect(x: 100, y: 1382, width: 800, height: 600))
        XCTAssertEqual(AXWindowLocator.index(ofFrameContaining: frame, in: [primary, above, left]), 1)
    }

    func testWindowOnADisplayLeftOfThePrimary() {
        let frame = AXWindowLocator.appKitFrame(position: CGPoint(x: -1500, y: 200), size: CGSize(width: 1000, height: 700), primaryScreenFrame: primary)
        XCTAssertEqual(frame, CGRect(x: -1500, y: 82, width: 1000, height: 700))
        XCTAssertEqual(AXWindowLocator.index(ofFrameContaining: frame, in: [primary, above, left]), 2)
    }

    /// A window across two displays belongs to the one that holds its center.
    func testWindowAcrossDisplaysBelongsToTheOneHoldingItsCenter() {
        let straddling = CGRect(x: -1000, y: 100, width: 1100, height: 500)    // center x = -450
        XCTAssertEqual(AXWindowLocator.index(ofFrameContaining: straddling, in: [primary, left]), 1)
        let offScreen = CGRect(x: 5000, y: 5000, width: 100, height: 100)
        XCTAssertNil(AXWindowLocator.index(ofFrameContaining: offScreen, in: [primary, left]))
    }
}

import AppKit
import ApplicationServices
import XCTest
@testable import RoteAX

final class AXReaderTests: XCTestCase {
    /// A pid no process has, so every Accessibility call to it fails.
    private func unusedPID() throws -> pid_t {
        try XCTUnwrap((90_000...99_999).reversed().first { kill(pid_t($0), 0) != 0 && errno == ESRCH }.map { pid_t($0) })
    }

    private func finder() throws -> AXUIElement {
        try XCTSkipUnless(AXIsProcessTrusted(), "needs Accessibility permission for the test runner")
        let app = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first, "Finder is not running")
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    func testOnlyNoValueAndUnsupportedAttributeCountAsAbsence() throws {
        XCTAssertEqual(try AXReader.classify(.success, "Safari" as NSString).get() as? String, "Safari")
        XCTAssertNil(try AXReader.classify(.noValue, nil).get())
        XCTAssertNil(try AXReader.classify(.attributeUnsupported, nil).get())
        for code in [AXError.cannotComplete, .invalidUIElement, .apiDisabled, .failure, .notImplemented] {
            XCTAssertThrowsError(try AXReader.classify(code, nil).get(), "\(code.rawValue)") { error in
                XCTAssertEqual(error as? AXReadError, AXReadError(code: code))
            }
        }
    }

    /// A busy, hung or quit app must not read as an app with an empty menu bar (spec §5.1, §11).
    /// macOS answers `.cannotComplete` here (`.apiDisabled` without permission); both are failures.
    func testUnreachableAppIsAFailureNotAnAbsence() throws {
        let ghost = AXUIElementCreateApplication(try unusedPID())
        XCTAssertThrowsError(try AXReader.read(ghost, kAXMenuBarAttribute).get())
        XCTAssertThrowsError(try AXReader.readElement(ghost, kAXMenuBarAttribute).get())
        XCTAssertThrowsError(try AXReader.readElements(ghost, kAXChildrenAttribute).get())
        XCTAssertThrowsError(try AXReader.readMultiple(ghost, [kAXRoleAttribute, kAXTitleAttribute]).get())

        // The Optional helpers keep folding every failure into "nothing".
        XCTAssertNil(AXReader.value(ghost, kAXMenuBarAttribute))
        XCTAssertNil(AXReader.element(ghost, kAXMenuBarAttribute))
        XCTAssertEqual(AXReader.elements(ghost, kAXChildrenAttribute), [])
        XCTAssertTrue(AXReader.multiple(ghost, [kAXRoleAttribute]).isEmpty)
    }

    func testUnsupportedAttributeIsAnAbsenceNotAFailure() throws {
        let finder = try finder()
        XCTAssertNil(try AXReader.read(finder, "AXRoteNoSuchAttribute").get())
    }

    func testElementHelpersKeepOnlyElements() throws {
        let finder = try finder()
        let menuBar = try XCTUnwrap(try AXReader.readElement(finder, kAXMenuBarAttribute).get())
        XCTAssertFalse(try AXReader.readElements(menuBar, kAXChildrenAttribute).get().isEmpty)
        XCTAssertNil(try AXReader.readElement(finder, kAXTitleAttribute).get(), "a string is not an element")
        XCTAssertEqual(try AXReader.readElements(finder, kAXTitleAttribute).get(), [], "nor an array of elements")
    }

    func testMultipleMapsValuesByIndexAndDropsMissingOnes() throws {
        let finder = try finder()
        let values = try AXReader.readMultiple(finder, [kAXRoleAttribute, "AXRoteNoSuchAttribute", kAXTitleAttribute]).get()
        XCTAssertEqual(values[kAXRoleAttribute] as? String, "AXApplication")
        XCTAssertNil(values["AXRoteNoSuchAttribute"])
        XCTAssertEqual(values[kAXTitleAttribute] as? String, "Finder")
    }
}

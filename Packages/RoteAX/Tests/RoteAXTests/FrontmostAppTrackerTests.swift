import AppKit
import XCTest
@testable import RoteAX

/// The tracker needs no Accessibility permission: these tests post synthetic activation
/// notifications on the workspace center it listens to.
@MainActor
final class FrontmostAppTrackerTests: XCTestCase {
    private final class Recorder {
        var reports: [AppIdentity?] = []
    }

    private func makeTracker() -> (FrontmostAppTracker, Recorder) {
        let tracker = FrontmostAppTracker()
        let recorder = Recorder()
        tracker.onActivate = { recorder.reports.append($0) }
        return (tracker, recorder)
    }

    private func postActivation(_ app: NSRunningApplication?) {
        let userInfo: [AnyHashable: Any]? = app.map { [NSWorkspace.applicationUserInfoKey: $0] }
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: userInfo
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func bundledApp() throws -> NSRunningApplication {
        try XCTUnwrap(NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier != nil && $0.processIdentifier != getpid() })
    }

    func testStartReportsTheFrontmostAppOnceAndIsIdempotent() throws {
        let (tracker, recorder) = makeTracker()
        defer { tracker.stop() }
        tracker.start()
        tracker.start()
        XCTAssertEqual(recorder.reports.count, 1, "a second start neither reports again nor registers twice")
        XCTAssertEqual(recorder.reports.first ?? nil, NSWorkspace.shared.frontmostApplication.flatMap(FrontmostAppTracker.identity(for:)))

        let app = try bundledApp()
        recorder.reports.removeAll()
        postActivation(app)
        XCTAssertEqual(recorder.reports, [FrontmostAppTracker.identity(for: app)])
    }

    func testActivationOfAnAppWithoutABundleIDIsReportedAsNil() throws {
        // `swift test` runs in the unbundled xctest tool, which is exactly such an app.
        let unbundled = NSRunningApplication.current
        try XCTSkipIf(unbundled.bundleIdentifier != nil, "needs a test runner without a bundle ID")
        let bundled = try bundledApp()
        let (tracker, recorder) = makeTracker()
        defer { tracker.stop() }
        tracker.start()
        recorder.reports.removeAll()

        postActivation(bundled)
        postActivation(unbundled)
        XCTAssertEqual(recorder.reports, [FrontmostAppTracker.identity(for: bundled), nil],
                       "the consumer must learn that the previous app is no longer frontmost")
    }

    func testActivationWithoutAnAppIsReportedAsNil() {
        let (tracker, recorder) = makeTracker()
        defer { tracker.stop() }
        tracker.start()
        recorder.reports.removeAll()

        postActivation(nil)
        XCTAssertEqual(recorder.reports, [nil])
    }

    func testStopSilencesAndRestartResumes() throws {
        let app = try bundledApp()
        let (tracker, recorder) = makeTracker()
        defer { tracker.stop() }
        tracker.start()
        tracker.stop()
        recorder.reports.removeAll()

        postActivation(app)
        XCTAssertEqual(recorder.reports, [], "no reports while stopped")

        tracker.start()
        XCTAssertEqual(recorder.reports.count, 1, "restart reports the frontmost app again")
        postActivation(app)
        XCTAssertEqual(recorder.reports.count, 2)
        XCTAssertEqual(recorder.reports.last ?? nil, FrontmostAppTracker.identity(for: app))
    }

    func testIdentityCopiesPidBundleIDAndName() throws {
        let app = try bundledApp()
        let identity = try XCTUnwrap(FrontmostAppTracker.identity(for: app))
        XCTAssertEqual(identity.pid, app.processIdentifier)
        XCTAssertEqual(identity.bundleID, app.bundleIdentifier)
        XCTAssertEqual(identity.name, app.localizedName ?? app.bundleIdentifier)
    }

    func testAppWithoutABundleIDHasNoIdentity() throws {
        let unbundled = NSRunningApplication.current
        try XCTSkipIf(unbundled.bundleIdentifier != nil, "needs a test runner without a bundle ID")
        XCTAssertNil(FrontmostAppTracker.identity(for: unbundled))
    }

    /// `identity(for:)` only reads fixed properties of a Sendable value, so actors and background
    /// code can map apps too; this compiles only while it stays nonisolated.
    nonisolated func testIdentityIsAvailableOffTheMainActor() {
        XCTAssertEqual(FrontmostAppTracker.identity(for: NSRunningApplication.current)?.pid ?? getpid(), getpid())
    }
}

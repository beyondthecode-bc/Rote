import XCTest
@testable import Rote
import RoteCore

/// The fakes and throwaway stores the other tests rely on stay off the user's real data.
@MainActor
final class TestIsolationTests: XCTestCase {
    func testATestSuiteIsWrittenInsideItsTemporaryDirectory() async {
        let testDefaults = TestDefaults()
        defer { testDefaults.remove() }
        let plist = URL(fileURLWithPath: testDefaults.name + ".plist")
        XCTAssertTrue(plist.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        XCTAssertNotEqual(testDefaults.defaults, UserDefaults.standard)

        testDefaults.defaults.set(1, forKey: "probe")
        testDefaults.defaults.synchronize()

        await waitUntil { FileManager.default.fileExists(atPath: plist.path) }
        XCTAssertNil(UserDefaults.standard.object(forKey: "probe"))
    }

    func testTheEngineHarnessKeepsItsStateInATemporaryDirectoryAndRemovesIt() async throws {
        let harness = try EngineHarness()
        XCTAssertTrue(harness.stateURL.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        XCTAssertNotEqual(harness.stateURL, StateStore.defaultFileURL())

        await harness.engine.start()
        harness.engine.resetStatistics()            // queues a debounced save
        await harness.tearDown()
        try await Task.sleep(for: .milliseconds(50))  // longer than the store's debounce

        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.directory.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.testDefaults.directory.path))
    }

    /// Never the process's own trust: a trusted test host would start the real activation observer
    /// and key monitors.
    func testTheEngineAsksTheInjectedPermissionCheck() async throws {
        var checks = 0
        let harness = try EngineHarness(isTrusted: {
            checks += 1
            return false
        })
        addTeardownBlock { @MainActor in await harness.tearDown() }

        await harness.engine.start()

        await waitUntil { checks >= 1 }
        XCTAssertFalse(harness.engine.permissionGranted)
    }
}

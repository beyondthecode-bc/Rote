import XCTest
@testable import RoteCore

/// Counts the write failures a store reports; the store calls it from its own actor.
private final class FailureLog: @unchecked Sendable {
    private let lock = NSLock()
    private var failures = 0

    func record(_ error: any Error) { lock.withLock { failures += 1 } }
    var count: Int { lock.withLock { failures } }
}

final class StateStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RoteStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var fileURL: URL { directory.appendingPathComponent("state.json") }

    /// A path whose parent is a regular file, so every write fails (like a `Rote` file where the
    /// folder belongs).
    private func unwritableFileURL() throws -> URL {
        let blocker = directory.appendingPathComponent("Rote")
        try Data().write(to: blocker)
        return blocker.appendingPathComponent("state.json")
    }

    private func sampleState() -> CoachState {
        var state = CoachState()
        let item = MenuItemRecord(bundleID: "com.apple.Safari", path: ["View", "Reload Page"], shortcut: Shortcut(modifiers: [.command], key: .character("R")))
        var record = ItemRecord(item: item)
        record.phase = .coaching
        record.menuUses = [Date(timeIntervalSince1970: 1_792_000_000)]
        state.items[record.identity] = record
        state.nudgesByDay["2026-10-18"] = 2
        return state
    }

    func testFreshWhenNoFile() async {
        let store = StateStore(fileURL: fileURL)
        let result = await store.load()
        XCTAssertEqual(result, .fresh)
    }

    func testRoundTrip() async throws {
        let store = StateStore(fileURL: fileURL)
        let state = sampleState()
        try await store.saveNow(state)
        let result = await store.load()
        XCTAssertEqual(result, .loaded(state))
    }

    func testDebounceWritesLatest() async throws {
        let store = StateStore(fileURL: fileURL, debounce: .milliseconds(50))
        var first = sampleState()
        first.nudgesByDay["2026-10-18"] = 1
        var second = sampleState()
        second.nudgesByDay["2026-10-18"] = 9
        await store.scheduleSave(first)
        await store.scheduleSave(second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "nothing is written before the debounce elapses")
        try await Task.sleep(for: .milliseconds(150))
        let result = await store.load()
        XCTAssertEqual(result, .loaded(second))
    }

    func testSupersededSaveDoesNotWriteEarly() async throws {
        let store = StateStore(fileURL: fileURL, debounce: .seconds(10))
        var first = sampleState()
        first.nudgesByDay["2026-10-18"] = 1
        await store.scheduleSave(first)
        await store.scheduleSave(sampleState())
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "a replaced save is dropped, not written at once")
        await store.flush()
        let result = await store.load()
        XCTAssertEqual(result, .loaded(sampleState()))
    }

    func testLaterChangeRestartsQuietPeriod() async throws {
        let store = StateStore(fileURL: fileURL, debounce: .seconds(1))
        var first = sampleState()
        first.nudgesByDay["2026-10-18"] = 1
        await store.scheduleSave(first)
        try await Task.sleep(for: .milliseconds(600))
        await store.scheduleSave(sampleState())
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "the write waits for a quiet period after the last change, not the first")
        await store.flush()
        let result = await store.load()
        XCTAssertEqual(result, .loaded(sampleState()))
    }

    func testFlushWritesImmediately() async throws {
        let store = StateStore(fileURL: fileURL, debounce: .seconds(10))
        await store.scheduleSave(sampleState())
        await store.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testFlushWithNothingScheduledLeavesSavedStateAlone() async throws {
        try await StateStore(fileURL: fileURL).saveNow(sampleState())
        let store = StateStore(fileURL: fileURL)
        let loaded = await store.load()
        XCTAssertEqual(loaded, .loaded(sampleState()))
        await store.flush()
        let again = await store.load()
        XCTAssertEqual(again, .loaded(sampleState()), "quitting without changes must not touch the file")
    }

    func testWriteCreatesMissingParentDirectory() async throws {
        let nested = directory.appendingPathComponent("Rote", isDirectory: true).appendingPathComponent("state.json")
        let store = StateStore(fileURL: nested, debounce: .seconds(10))
        await store.scheduleSave(sampleState())
        await store.flush()
        let result = await store.load()
        XCTAssertEqual(result, .loaded(sampleState()), "the first launch has no Rote folder yet")
    }

    func testFlushReportsWriteFailure() async throws {
        let failures = FailureLog()
        let store = StateStore(fileURL: try unwritableFileURL(), debounce: .seconds(10), onWriteFailure: { failures.record($0) })
        await store.scheduleSave(sampleState())
        await store.flush()
        XCTAssertEqual(failures.count, 1, "a write that fails on quit is reported, not swallowed")
    }

    func testDebouncedWriteReportsFailure() async throws {
        let failures = FailureLog()
        let store = StateStore(fileURL: try unwritableFileURL(), debounce: .milliseconds(50), onWriteFailure: { failures.record($0) })
        await store.scheduleSave(sampleState())
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(failures.count, 1, "a debounced write that fails is reported, not swallowed")
    }

    func testLoadsVersionOneGoldenFile() async throws {
        try Data(CoachFixtures.versionOneGolden.utf8).write(to: fileURL)
        let result = await StateStore(fileURL: fileURL).load()
        XCTAssertEqual(result, .loaded(CoachFixtures.everyFieldState()), "a file written by version 1 loads through the store")
    }

    func testCorruptFileIsQuarantined() async throws {
        try "{ this is not json".write(to: fileURL, atomically: true, encoding: .utf8)
        let store = StateStore(fileURL: fileURL)
        let result = await store.load()
        guard case .recovered(let name) = result else { return XCTFail("expected recovery, got \(result)") }
        XCTAssertNotNil(name.range(of: #"^state\.corrupt-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}Z\.json$"#, options: .regularExpression),
                        "the name carries its date (state.corrupt-<date>.json), so a later quarantine cannot replace this one; got \(name)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path))
    }

    func testNewerSchemaIsQuarantined() async throws {
        let store = StateStore(fileURL: fileURL)
        try await store.saveNow(sampleState())
        let current = await store.load()
        XCTAssertEqual(current, .loaded(sampleState()), "the same state at the current version loads, so only the version moves it aside")
        var state = sampleState()
        state.schemaVersion = CoachState.currentSchemaVersion + 1
        try await store.saveNow(state)
        let original = try Data(contentsOf: fileURL)
        let result = await store.load()
        guard case .recovered(let name) = result else { return XCTFail("expected recovery, got \(result)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "the newer file is moved aside, so this build's next save cannot overwrite it")
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(name)), original, "the newer file is kept intact")
    }
}

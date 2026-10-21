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
        // Wait for the write rather than a fixed time: at background priority (release.sh runs under
        // `taskpolicy -b`) macOS may fire a 50 ms timer far later. The write is atomic, so once the
        // file exists it holds a whole state.
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: fileURL.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let result = await store.load()
        XCTAssertEqual(result, .loaded(second), "only the latest of two quick saves is written")
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

    /// Audit M1: a file with `Int.max` counters on two records of one identity trapped the start-up
    /// merge on every launch. The store moves it aside like any unreadable file and Rote starts fresh.
    func testTamperedCountersAreQuarantined() async throws {
        let item = """
        {"bundleID":"com.apple.Safari","path":["View","Reload Page"],"shortcut":{"key":{"character":{"_0":"R"}},"modifiers":8}}
        """
        let json = """
        {"schemaVersion":1,"items":{
        "a":{"item":\(item),"phase":"coaching","nudgeCount":\(Int.max),"regressions":\(Int.max),"menuUsesSinceLastNudge":\(Int.max)},
        "b":{"item":\(item),"phase":"learned","nudgeCount":\(Int.max),"regressions":\(Int.max),"shortcutUsesSinceCoaching":\(Int.max)}},
        "nudgesByDay":{"2026-10-18":\(Int.max)}}
        """
        try json.write(to: fileURL, atomically: true, encoding: .utf8)
        let store = StateStore(fileURL: fileURL)
        let result = await store.load()
        guard case .recovered(let name) = result else { return XCTFail("expected recovery, got \(result)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8), json, "the file is kept intact for inspection")
        // What the engine does next with a fresh state: re-key, prune, handle; none of it traps.
        var state = CoachState()
        state.rekeyItems()
        let coach = Coach(policy: .default, calendar: CoachFixtures.calendar)
        coach.prune(state: &state, now: Date())
        XCTAssertEqual(coach.handle(CoachFixtures.menu(CoachFixtures.reload, at: 0), state: &state, context: CoachFixtures.ctx), .record)
        let again = await store.load()
        XCTAssertEqual(again, .fresh)
    }

    func testOutOfRangeCollectionsAreQuarantined() async throws {
        let days = (0..<(CoachState.maxDecodedCollectionCount + 1)).map { "\"d\($0)\":1" }.joined(separator: ",")
        try "{\"schemaVersion\":1,\"nudgesByDay\":{\(days)}}".write(to: fileURL, atomically: true, encoding: .utf8)
        let result = await StateStore(fileURL: fileURL).load()
        guard case .recovered = result else { return XCTFail("expected recovery, got \(result)") }
    }

    /// A file past the size cap is moved aside unread: no parse, however many entries it holds.
    func testOversizedFileIsQuarantinedWithoutParsing() async throws {
        try await StateStore(fileURL: fileURL).saveNow(sampleState())
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int)
        let strict = StateStore(fileURL: fileURL, maxFileSize: size - 1)
        guard case .recovered = await strict.load() else { return XCTFail("expected recovery") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        try await StateStore(fileURL: fileURL).saveNow(sampleState())
        let exact = StateStore(fileURL: fileURL, maxFileSize: size)
        let atCap = await exact.load()
        XCTAssertEqual(atCap, .loaded(sampleState()), "a file at the cap still loads")
        XCTAssertGreaterThanOrEqual(StateStore.defaultMaxFileSize, 64 * 1024 * 1024)
    }

    /// Long use lists and logs from an earlier build are trimmed to the caps, not quarantined.
    func testLegacyLongListsLoadTrimmed() async throws {
        var state = sampleState()
        var record = try XCTUnwrap(state.items.values.first)
        record.menuUses = (0..<(ItemRecord.maxMenuUses + 20)).map { Date(timeIntervalSince1970: 1_792_000_000 + Double($0)) }
        state.items[record.identity] = record
        try await StateStore(fileURL: fileURL).saveNow(state)
        guard case .loaded(let loaded) = await StateStore(fileURL: fileURL).load() else { return XCTFail("expected a load") }
        XCTAssertEqual(loaded.items[record.identity]?.menuUses.count, ItemRecord.maxMenuUses)
        XCTAssertEqual(loaded.items[record.identity]?.menuUses.last, record.menuUses.last)
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

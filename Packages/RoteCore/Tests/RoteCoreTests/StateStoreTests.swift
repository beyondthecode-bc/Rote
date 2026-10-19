import XCTest
@testable import RoteCore

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

    func testFlushWritesImmediately() async throws {
        let store = StateStore(fileURL: fileURL, debounce: .seconds(10))
        await store.scheduleSave(sampleState())
        await store.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCorruptFileIsQuarantined() async throws {
        try "{ this is not json".write(to: fileURL, atomically: true, encoding: .utf8)
        let store = StateStore(fileURL: fileURL)
        let result = await store.load()
        guard case .recovered(let name) = result else { return XCTFail("expected recovery, got \(result)") }
        XCTAssertTrue(name.hasPrefix("state.corrupt-"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path))
    }

    func testNewerSchemaIsQuarantined() async throws {
        var state = sampleState()
        state.schemaVersion = CoachState.currentSchemaVersion + 1
        let store = StateStore(fileURL: fileURL)
        try await store.saveNow(state)
        let result = await store.load()
        guard case .recovered = result else { return XCTFail("expected recovery, got \(result)") }
    }
}

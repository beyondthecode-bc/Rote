import XCTest
@testable import RoteCore

/// A `state.json` is user-writable and shared with every process running as the user, so what it
/// says is clamped on the way in and anything out of range is reported, so the store can move the
/// file aside instead of trapping on the first increment (audit M1).
final class CoachStateTests: XCTestCase {
    private typealias Fx = CoachFixtures

    private func decoder(reporting report: CoachStateDecodingReport? = nil) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let report { decoder.userInfo[CoachState.decodingReportKey] = report }
        return decoder
    }

    private func decode(_ json: String, report: CoachStateDecodingReport? = nil) throws -> CoachState {
        try decoder(reporting: report).decode(CoachState.self, from: Data(json.utf8))
    }

    private let reloadJSON = """
    {"bundleID":"com.apple.Safari","path":["View","Reload Page"],"shortcut":{"key":{"character":{"_0":"R"}},"modifiers":8}}
    """

    /// One record whose counters are `counts`, keyed under `key`.
    private func record(key: String, nudgeCount: Int = 0, regressions: Int = 0, menuUsesSinceLastNudge: Int = 0, shortcutUsesSinceCoaching: Int = 0, extra: String = "") -> String {
        """
        "\(key)":{"item":\(reloadJSON),"phase":"coaching","nudgeCount":\(nudgeCount),"regressions":\(regressions),
        "menuUsesSinceLastNudge":\(menuUsesSinceLastNudge),"shortcutUsesSinceCoaching":\(shortcutUsesSinceCoaching)\(extra)}
        """
    }

    private func state(items: String..., rest: String = "") -> String {
        "{\"schemaVersion\":1,\"items\":{\(items.joined(separator: ","))}\(rest)}"
    }

    // MARK: Counters

    func testWellFormedFileDecodesUnchangedAndReportsNothing() throws {
        let report = CoachStateDecodingReport()
        let state = try decoder(reporting: report).decode(CoachState.self, from: Data(Fx.versionOneGolden.utf8))
        XCTAssertEqual(state, Fx.everyFieldState())
        XCTAssertTrue(report.isEmpty, "\(report.issues)")
    }

    func testCountersAreClampedToTheirRangeAndReported() throws {
        let report = CoachStateDecodingReport()
        let state = try decode(state(items: record(key: "a", nudgeCount: Int.max, regressions: -5, menuUsesSinceLastNudge: ItemRecord.maxCounter + 1)), report: report)
        let record = try XCTUnwrap(state.items["a"])
        XCTAssertEqual(record.nudgeCount, ItemRecord.maxCounter)
        XCTAssertEqual(record.regressions, 0)
        XCTAssertEqual(record.menuUsesSinceLastNudge, ItemRecord.maxCounter)
        XCTAssertEqual(record.shortcutUsesSinceCoaching, 0)
        XCTAssertEqual(report.issues.count, 3, "\(report.issues)")
    }

    func testCountersAtTheCapAreInRange() throws {
        let report = CoachStateDecodingReport()
        let state = try decode(state(items: record(key: "a", nudgeCount: ItemRecord.maxCounter, regressions: 0)), report: report)
        XCTAssertEqual(state.items["a"]?.nudgeCount, ItemRecord.maxCounter)
        XCTAssertTrue(report.isEmpty, "\(report.issues)")
    }

    func testDayCountersAreClampedAndReported() throws {
        let report = CoachStateDecodingReport()
        let state = try decode(state(items: record(key: "a"), rest: ",\"nudgesByDay\":{\"2026-10-12\":\(Int.max),\"2026-10-13\":-1,\"2026-10-14\":4}"), report: report)
        XCTAssertEqual(state.nudgesByDay, ["2026-10-12": ItemRecord.maxCounter, "2026-10-13": 0, "2026-10-14": 4])
        XCTAssertEqual(report.issues.count, 2, "\(report.issues)")
    }

    /// The audit's crash: two records of one identity, both at `Int.max`, trapped in the start-up
    /// merge on every launch. Decoding clamps them and the merge saturates, so the state is usable
    /// whatever the store then decides to do with the file.
    func testIntMaxCountersOnTwoRecordsOfOneIdentityMergeWithoutTrapping() throws {
        let report = CoachStateDecodingReport()
        var state = try decode(state(items: record(key: "a", nudgeCount: Int.max, regressions: Int.max), record(key: "b", nudgeCount: Int.max, regressions: Int.max)), report: report)
        XCTAssertFalse(report.isEmpty)
        state.rekeyItems()
        let merged = try XCTUnwrap(state.items[Fx.reload.identity])
        XCTAssertEqual(state.items.count, 1)
        XCTAssertEqual(merged.nudgeCount, ItemRecord.maxCounter)
        XCTAssertEqual(merged.regressions, ItemRecord.maxCounter)
        let c = Fx.coach()
        c.prune(state: &state, now: Fx.base)
        _ = c.handle(Fx.menu(Fx.reload, at: 0), state: &state, context: Fx.ctx)
    }

    func testMergeSaturatesInsteadOfTrapping() {
        var a = ItemRecord(item: Fx.reload)
        a.nudgeCount = Int.max
        a.regressions = Int.max - 1
        var b = ItemRecord(item: Fx.reload)
        b.nudgeCount = 2
        b.regressions = Int.max
        let merged = CoachState.merge(a, b)
        XCTAssertEqual(merged.nudgeCount, ItemRecord.maxCounter)
        XCTAssertEqual(merged.regressions, ItemRecord.maxCounter)
    }

    /// Two in-range records of one identity whose counters add up past the cap are not a file Rote
    /// wrote: no merge can represent them, so the file is reported for quarantine.
    func testCollidingRecordsThatOverflowTheCapAreReported() throws {
        let report = CoachStateDecodingReport()
        _ = try decode(state(items: record(key: "a", nudgeCount: 600_000), record(key: "b", nudgeCount: 600_000)), report: report)
        XCTAssertEqual(report.issues.count, 1, "\(report.issues)")
        let fine = CoachStateDecodingReport()
        _ = try decode(state(items: record(key: "a", nudgeCount: 3), record(key: "b", nudgeCount: 4)), report: fine)
        XCTAssertTrue(fine.isEmpty, "a re-keyed file from an identity-rule change merges silently: \(fine.issues)")
    }

    // MARK: Arrays

    private func dates(_ count: Int, from offset: TimeInterval = 0) -> String {
        let formatter = ISO8601DateFormatter()
        return (0..<count).map { "\"\(formatter.string(from: Fx.base.addingTimeInterval(offset + Double($0) * 60)))\"" }.joined(separator: ",")
    }

    /// A file written by 1.0.x may carry more menu uses than the cap: the latest are kept, silently.
    func testLongUseListsKeepTheLatestWithoutAReport() throws {
        let report = CoachStateDecodingReport()
        let unsorted = dates(30, from: 100_000) + "," + dates(40)
        let state = try decode(state(items: record(key: "a", extra: ",\"menuUses\":[\(unsorted)],\"shortcutUses\":[\(dates(70))]")), report: report)
        let record = try XCTUnwrap(state.items["a"])
        XCTAssertEqual(record.menuUses.count, ItemRecord.maxMenuUses)
        XCTAssertEqual(record.menuUses, record.menuUses.sorted())
        XCTAssertEqual(record.menuUses.last, Fx.base.addingTimeInterval(100_000 + 29 * 60), "the latest uses survive, not the first in file order")
        XCTAssertEqual(record.shortcutUses.count, ItemRecord.maxShortcutUses)
        XCTAssertEqual(record.shortcutUses.first, Fx.base.addingTimeInterval(20 * 60))
        XCTAssertTrue(report.isEmpty, "\(report.issues)")
    }

    func testLongLogKeepsTheLatestEntries() throws {
        let entry = "{\"at\":\"2026-10-12T00:00:00Z\",\"kind\":\"menuUsed\"},"
        let last = "{\"at\":\"2026-10-13T00:00:00Z\",\"kind\":\"shortcutUsed\"}"
        let report = CoachStateDecodingReport()
        let state = try decode(state(items: record(key: "a"), rest: ",\"log\":[\(String(repeating: entry, count: CoachState.maxLogEntries))\(last)]"), report: report)
        XCTAssertEqual(state.log.count, CoachState.maxLogEntries)
        XCTAssertEqual(state.log.last?.kind, .shortcutUsed, "the newest entry is kept")
        XCTAssertTrue(report.isEmpty, "\(report.issues)")
    }

    /// Ten million dates: no Rote wrote that. The array is dropped unread, so the decode costs the
    /// JSON scan and nothing more, and the report sends the file to quarantine.
    func testTenMillionEntryArrayIsDroppedUnreadAndReported() throws {
        let entry = "\"2026-10-12T00:05:00Z\","
        var json = "{\"schemaVersion\":1,\"items\":{\"a\":{\"item\":\(reloadJSON),\"phase\":\"coaching\",\"menuUses\":["
        json.reserveCapacity(json.utf8.count + 10_000_000 * entry.utf8.count + 64)
        json += String(repeating: entry, count: 10_000_000 - 1) + "\"2026-10-12T00:05:00Z\"]}}}"
        let data = Data(json.utf8)
        json = ""
        let report = CoachStateDecodingReport()
        let started = ContinuousClock.now
        let state = try decoder(reporting: report).decode(CoachState.self, from: data)
        let elapsed = started.duration(to: .now)
        XCTAssertEqual(state.items["a"]?.menuUses, [])
        XCTAssertEqual(report.issues.count, 1, "\(report.issues)")
        XCTAssertLessThan(elapsed, .seconds(60), "the dates were not parsed one by one")
    }

    func testOversizedDictionariesAreDroppedAndReported() throws {
        let report = CoachStateDecodingReport()
        let days = (0..<(CoachState.maxDecodedCollectionCount + 1)).map { "\"d\($0)\":1" }.joined(separator: ",")
        let state = try decode(state(items: record(key: "a"), rest: ",\"nudgesByDay\":{\(days)}"), report: report)
        XCTAssertTrue(state.nudgesByDay.isEmpty)
        XCTAssertEqual(report.issues.count, 1, "\(report.issues)")
    }

    func testWithoutAReportTheValuesAreStillClamped() throws {
        let state = try decode(state(items: record(key: "a", nudgeCount: Int.max)))
        XCTAssertEqual(state.items["a"]?.nudgeCount, ItemRecord.maxCounter)
    }
}

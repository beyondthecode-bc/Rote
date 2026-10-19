import Observation
import XCTest
@testable import Rote
import RoteAX
import RoteCore

/// Pauses and their persistence, loading saved state, and the daily prune.
@MainActor
final class CoachEngineStateTests: XCTestCase {
    private let save = Fixtures.item(["File", "Save"], "S")

    private func makeHarness(pruneInterval: TimeInterval = 86_400) throws -> EngineHarness {
        let harness = try EngineHarness(pruneInterval: pruneInterval)
        addTeardownBlock { @MainActor in await harness.tearDown() }
        return harness
    }

    private func savedPause(_ h: EngineHarness) -> Date? {
        h.defaults.object(forKey: CoachEngine.pauseUntilKey) as? Date
    }

    // MARK: Pausing

    func testPauseForAnHourIsSavedAndResumeClearsIt() async throws {
        let h = try makeHarness()
        await h.engine.start()

        h.engine.pause(for: 3_600)

        let until = try XCTUnwrap(h.engine.pauseUntil)
        XCTAssertEqual(until.timeIntervalSinceNow, 3_600, accuracy: 5)
        XCTAssertTrue(h.engine.isPaused)
        XCTAssertFalse(h.engine.isPausedUntilResumed)
        XCTAssertEqual(savedPause(h), until)

        h.engine.resume()

        XCTAssertNil(h.engine.pauseUntil)
        XCTAssertFalse(h.engine.isPaused)
        XCTAssertNil(savedPause(h))
    }

    func testPauseUntilTomorrowEndsAtTheNextLocalMidnight() async throws {
        let h = try makeHarness()
        await h.engine.start()

        h.engine.pauseUntilTomorrow()

        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
        XCTAssertEqual(h.engine.pauseUntil, midnight)
        XCTAssertEqual(savedPause(h), midnight)
        XCTAssertTrue(h.engine.isPaused)
        XCTAssertFalse(h.engine.isPausedUntilResumed)
    }

    func testPauseUntilResumedHasNoDeadline() async throws {
        let h = try makeHarness()
        await h.engine.start()

        h.engine.pauseUntilResumed()

        XCTAssertEqual(h.engine.pauseUntil, .distantFuture)
        XCTAssertEqual(savedPause(h), .distantFuture)
        XCTAssertTrue(h.engine.isPaused)
        XCTAssertTrue(h.engine.isPausedUntilResumed)

        h.engine.resume()
        XCTAssertFalse(h.engine.isPausedUntilResumed)
        XCTAssertNil(savedPause(h))
    }

    func testWhilePausedMenuUsesAreRecordedButNotNudged() async throws {
        let h = try makeHarness()
        await h.engine.start()
        await h.activate(Fixtures.appA, serving: Fixtures.tree([Fixtures.menu("File", [save])]))
        h.engine.pause(for: 3_600)

        for _ in 0..<3 { h.menuPick(save) }
        XCTAssertTrue(h.nudges.isEmpty)
        XCTAssertEqual(h.record(save)?.menuUses.count, 3)

        h.engine.resume()
        h.menuPick(save)
        XCTAssertEqual(h.nudges.map(\.identity), [save.identity])
    }

    func testAPauseEndsOnItsOwnAndPublishesTheChange() async throws {
        let h = try makeHarness()
        await h.engine.start()
        h.engine.pause(for: 0.05)
        XCTAssertTrue(h.engine.isPaused)

        let published = expectation(description: "pauseUntil change published")
        withObservationTracking {
            _ = h.engine.pauseUntil
        } onChange: {
            published.fulfill()
        }
        await fulfillment(of: [published], timeout: 1)

        XCTAssertNil(h.engine.pauseUntil)
        XCTAssertFalse(h.engine.isPaused)
        XCTAssertNil(savedPause(h))
    }

    func testANewPauseReplacesTheEarlierDeadline() async throws {
        let h = try makeHarness()
        await h.engine.start()
        h.engine.pause(for: 0.05)
        h.engine.pause(for: 3_600)

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(h.engine.isPaused)
        XCTAssertEqual(try XCTUnwrap(h.engine.pauseUntil).timeIntervalSinceNow, 3_600, accuracy: 5)
        XCTAssertNotNil(savedPause(h))
    }

    func testStartRestoresASavedPause() async throws {
        let h = try makeHarness()
        let deadline = Date().addingTimeInterval(3_600)
        h.defaults.set(deadline, forKey: CoachEngine.pauseUntilKey)

        await h.engine.start()

        XCTAssertEqual(h.engine.pauseUntil, deadline)
        XCTAssertTrue(h.engine.isPaused)
        XCTAssertEqual(savedPause(h), deadline)
    }

    func testStartRestoresAPauseUntilResumed() async throws {
        let h = try makeHarness()
        h.defaults.set(Date.distantFuture, forKey: CoachEngine.pauseUntilKey)

        await h.engine.start()

        XCTAssertTrue(h.engine.isPausedUntilResumed)
        XCTAssertTrue(h.engine.isPaused)
    }

    func testStartDropsAPauseThatEndedWhileRoteWasNotRunning() async throws {
        let h = try makeHarness()
        h.defaults.set(Date().addingTimeInterval(-60), forKey: CoachEngine.pauseUntilKey)

        await h.engine.start()

        XCTAssertNil(h.engine.pauseUntil)
        XCTAssertFalse(h.engine.isPaused)
        XCTAssertNil(savedPause(h))
    }

    func testARestoredPauseStillEndsOnTime() async throws {
        let h = try makeHarness()
        h.defaults.set(Date().addingTimeInterval(0.05), forKey: CoachEngine.pauseUntilKey)

        await h.engine.start()
        XCTAssertTrue(h.engine.isPaused)

        await waitUntil(timeout: .seconds(1)) { h.engine.pauseUntil == nil }
        XCTAssertNil(savedPause(h))
    }

    // MARK: Saved state

    func testStartLoadsTheSavedState() async throws {
        let h = try makeHarness()
        var state = CoachState()
        var record = ItemRecord(item: save)
        record.phase = .coaching
        record.menuUses = [Date().addingTimeInterval(-60)]
        state.items[save.identity] = record
        try await h.save(state)

        await h.engine.start()

        XCTAssertEqual(h.record(save)?.phase, .coaching)
        XCTAssertNil(h.engine.recoveredCorruptFile)
    }

    func testAnUnreadableStateFileIsReportedOnceAndSetAside() async throws {
        let h = try makeHarness()
        try Data("not json".utf8).write(to: h.stateURL)

        await h.engine.start()

        let name = try XCTUnwrap(h.engine.recoveredCorruptFile)
        XCTAssertTrue(name.hasPrefix("state.corrupt-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: h.directory.url.appendingPathComponent(name).path))
        XCTAssertTrue(h.engine.state.items.isEmpty)

        h.engine.acknowledgeRecoveryNotice()
        XCTAssertNil(h.engine.recoveredCorruptFile)
    }

    func testStartPrunesWhatThePolicyNoLongerNeeds() async throws {
        let h = try makeHarness()
        var state = CoachState()
        var record = ItemRecord(item: save)
        record.snoozedUntil = Date().addingTimeInterval(-60)   // observed, no uses, snooze over
        state.items[save.identity] = record
        try await h.save(state)

        await h.engine.start()

        XCTAssertNil(h.record(save))
    }

    // MARK: Daily prune

    /// A muted item with no uses survives a prune; once unmuted it is an empty observed record,
    /// which the next prune forgets.
    private func startWithAnUnmutedEmptyRecord(_ h: EngineHarness) async throws {
        var state = CoachState()
        var record = ItemRecord(item: save)
        record.phase = .muted
        state.items[save.identity] = record
        try await h.save(state)
        await h.engine.start()
        XCTAssertEqual(h.record(save)?.phase, .muted, "a muted record survives the prune at start")
        h.engine.unmute(save.identity)
        XCTAssertEqual(h.record(save)?.phase, .observed)
    }

    func testAnActivationWithinADayOfTheLastPruneDoesNotPrune() async throws {
        let h = try makeHarness()
        try await startWithAnUnmutedEmptyRecord(h)

        await h.activate(Fixtures.appA, serving: Fixtures.tree([]))

        XCTAssertNotNil(h.record(save))
    }

    func testTheFirstActivationAfterThePruneIntervalPrunesAndSaves() async throws {
        let h = try makeHarness(pruneInterval: 0.02)
        try await startWithAnUnmutedEmptyRecord(h)
        try await Task.sleep(for: .milliseconds(40))

        h.activate(nil)                   // no app to coach: nothing runs
        h.activate(Fixtures.ownApp)       // Rote in front: nothing runs
        XCTAssertNotNil(h.record(save))

        h.activate(Fixtures.appA)
        XCTAssertNil(h.record(save))
        await waitUntil { await h.savedState().map { $0.items[self.save.identity] == nil } ?? false }
    }

    func testThePruneIntervalRestartsAfterEachPrune() async throws {
        let h = try makeHarness(pruneInterval: 0.05)
        let open = Fixtures.item(["File", "Open"], "O")
        var state = CoachState()
        for item in [save, open] {
            var record = ItemRecord(item: item)
            record.phase = .muted
            state.items[item.identity] = record
        }
        try await h.save(state)
        await h.engine.start()
        h.engine.unmute(save.identity)
        try await Task.sleep(for: .milliseconds(70))

        h.activate(Fixtures.appA)         // prunes
        XCTAssertNil(h.record(save))
        XCTAssertEqual(h.record(open)?.phase, .muted)

        h.engine.unmute(open.identity)
        h.activate(Fixtures.appB)         // right after a prune: none due
        XCTAssertEqual(h.record(open)?.phase, .observed)
    }
}

import XCTest
@testable import Rote
import RoteCore

/// The HUD's lifecycle with a 50 ms display time: auto-dismiss, hover hold, and the snooze menu.
@MainActor
final class NudgeControllerTests: XCTestCase {
    private var events: [String] = []
    private let save = ItemRecord(item: Fixtures.item(["File", "Save"], "S"))
    private let open = ItemRecord(item: Fixtures.item(["File", "Open"], "O"))

    private func makeController() -> NudgeController {
        let testDefaults = TestDefaults()
        let settings = AppSettings(defaults: testDefaults.defaults)
        settings.hudDuration = 0.05
        let controller = NudgeController(settings: settings)
        controller.onDismiss = { [weak self] in self?.events.append("dismiss") }
        controller.onSnooze = { [weak self] identity in self?.events.append("snooze \(identity)") }
        controller.onMute = { [weak self] identity in self?.events.append("mute \(identity)") }
        controller.onPauseHour = { [weak self] in self?.events.append("pause") }
        addTeardownBlock { @MainActor in
            controller.onDismiss = nil
            controller.dismiss()
            testDefaults.remove()
        }
        return controller
    }

    private func show(_ record: ItemRecord, on controller: NudgeController) {
        controller.show(record, appName: "Alpha", appIcon: nil)
    }

    /// Longer than the display time, so a nudge that should have gone has gone.
    private func outlastTheDisplayTime() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    func testANudgeDismissesItselfAfterTheDisplayTime() async throws {
        let controller = makeController()
        show(save, on: controller)
        XCTAssertTrue(controller.isShowing)
        XCTAssertEqual(events, [])

        await waitUntil(timeout: .seconds(1)) { !controller.isShowing }
        XCTAssertEqual(events, ["dismiss"])
    }

    func testHoveringHoldsTheNudgeUntilThePointerLeaves() async throws {
        let controller = makeController()
        show(save, on: controller)
        controller.setHovering(true)

        try await outlastTheDisplayTime()
        XCTAssertTrue(controller.isShowing)
        XCTAssertEqual(events, [])

        controller.setHovering(false)
        await waitUntil(timeout: .seconds(1)) { !controller.isShowing }
        XCTAssertEqual(events, ["dismiss"])
    }

    func testHoverWithNoNudgeOnScreenHoldsNothing() async throws {
        let controller = makeController()
        controller.setHovering(true)
        controller.setHovering(false)
        try await outlastTheDisplayTime()
        XCTAssertFalse(controller.isShowing)
        XCTAssertEqual(events, [])

        controller.setHovering(true)      // a pointer resting where the next card appears
        show(save, on: controller)
        await waitUntil(timeout: .seconds(1)) { !controller.isShowing }
        XCTAssertEqual(events, ["dismiss"])
    }

    func testTheNextNudgeDropsTheHoverOfThePreviousOne() async throws {
        let controller = makeController()
        show(save, on: controller)
        controller.setHovering(true)

        show(open, on: controller)
        XCTAssertTrue(controller.isShowing)
        await waitUntil(timeout: .seconds(1)) { !controller.isShowing }
        XCTAssertEqual(events, ["dismiss"])
    }

    func testDismissDropsTheHover() async throws {
        let controller = makeController()
        show(save, on: controller)
        controller.setHovering(true)
        controller.dismiss()
        XCTAssertFalse(controller.isShowing)
        XCTAssertEqual(events, ["dismiss"])

        show(open, on: controller)
        await waitUntil(timeout: .seconds(1)) { !controller.isShowing }
        XCTAssertEqual(events, ["dismiss", "dismiss"])
    }

    func testLeavingAfterTheNudgeWentSchedulesNothing() async throws {
        let controller = makeController()
        show(save, on: controller)
        controller.setHovering(true)
        controller.dismiss()
        controller.setHovering(false)     // the pointer leaves the fading card

        try await outlastTheDisplayTime()
        XCTAssertEqual(events, ["dismiss"])
    }

    func testSnoozeReportsTheItemAndDismissesOnce() async throws {
        let controller = makeController()
        show(save, on: controller)
        controller.snoozeCurrent()

        XCTAssertFalse(controller.isShowing)
        XCTAssertEqual(events, ["snooze \(save.identity)", "dismiss"])
        try await outlastTheDisplayTime()
        XCTAssertEqual(events, ["snooze \(save.identity)", "dismiss"])
    }

    func testMuteReportsTheItemAndDismissesOnce() async throws {
        let controller = makeController()
        show(save, on: controller)
        controller.muteCurrent()

        XCTAssertFalse(controller.isShowing)
        XCTAssertEqual(events, ["mute \(save.identity)", "dismiss"])
        try await outlastTheDisplayTime()
        XCTAssertEqual(events, ["mute \(save.identity)", "dismiss"])
    }

    func testPauseForAnHourReportsAndDismissesOnce() async throws {
        let controller = makeController()
        show(save, on: controller)
        controller.pauseForAnHour()

        XCTAssertFalse(controller.isShowing)
        XCTAssertEqual(events, ["pause", "dismiss"])
        try await outlastTheDisplayTime()
        XCTAssertEqual(events, ["pause", "dismiss"])
    }

    func testSnoozeAndMuteActOnTheNudgeOnScreen() {
        let controller = makeController()
        show(save, on: controller)
        show(open, on: controller)
        controller.muteCurrent()
        XCTAssertEqual(events, ["mute \(open.identity)", "dismiss"])
    }

    func testWithNoNudgeOnScreenSnoozeMuteAndDismissDoNothing() {
        let controller = makeController()
        controller.snoozeCurrent()
        controller.muteCurrent()
        controller.dismiss()
        XCTAssertEqual(events, [])
    }
}

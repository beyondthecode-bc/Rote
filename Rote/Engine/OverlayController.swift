import AppKit
import Observation
import RoteCore
import SwiftUI

/// Turns key events into the hold gesture and shows the sheet (spec §7.2).
@MainActor
@Observable
final class OverlayController {
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private unowned let engine: CoachEngine
    @ObservationIgnored private var detector = HoldDetector()
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private let panel = OverlayPanel()

    /// Onboarding step 3 watches this.
    private(set) var hasShownOnce = false

    private static let hotkeyKeyCode: UInt16 = 40      // K
    private static let escapeKeyCode: UInt16 = 53

    init(settings: AppSettings, engine: CoachEngine) {
        self.settings = settings
        self.engine = engine
    }

    var isVisible: Bool { detector.isShowing }

    func handle(_ event: KeyEventMonitor.Event) {
        switch event {
        case .flagsChanged(let modifiers):
            guard settings.overlayTrigger != .stickyHotkey else { return }
            let target: Modifiers = settings.overlayTrigger == .holdOption ? [.option] : [.command]
            if modifiers == target {
                apply(detector.handle(.triggerHeld))
            } else if modifiers.isEmpty {
                apply(detector.handle(.triggerReleased))
            } else {
                apply(detector.handle(.otherModifierChange))
            }
        case .keyDown(let press, _):
            let isHotkey = !press.isRepeat && press.keyCode == Self.hotkeyKeyCode && press.modifiers == [.control, .option, .command]
            let isEscapeWhileSticky = !press.isRepeat && press.keyCode == Self.escapeKeyCode && detector.isSticky
            if isHotkey || isEscapeWhileSticky {
                apply(detector.handle(.stickyToggle))
            } else {
                apply(detector.handle(.keyDown))
            }
        case .mouseDown:
            apply(detector.handle(.mouseDown))
        }
    }

    private func apply(_ output: HoldDetector.Output) {
        switch output {
        case .none:
            break
        case .armTimer(let token):
            timer?.cancel()
            let delay = settings.holdDelayMs
            timer = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.apply(self.detector.handle(.timerFired(token)))
            }
        case .disarmTimer:
            timer?.cancel()
            timer = nil
        case .show:
            show()
        case .hide:
            hide()
        }
    }

    private func show() {
        guard !engine.isMenuOpen, let tree = engine.currentTree, let app = engine.currentApp else {
            detector = HoldDetector()        // nothing to show; forget the gesture
            return
        }
        let coaching = Set(engine.state.items.values.filter { $0.phase == .coaching }.map(\.identity))
        let learned = Set(engine.state.items.values.filter { $0.phase == .learned }.map(\.identity))
        let hint = detector.isSticky
            ? l("overlay.stickyHint")
            : l("overlay.releaseHint", settings.overlayTrigger == .holdOption ? "⌥" : "⌘")
        let view = ShortcutSheetView(
            tree: tree,
            appIcon: AppInfo.resolve(app.bundleID).icon,
            coaching: coaching,
            learned: learned,
            showAppleMenu: settings.showAppleMenu,
            showItemsWithoutShortcuts: settings.showItemsWithoutShortcuts,
            dismissHint: hint
        )

        let screen = NudgeController.targetScreen()
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: screen.frame.height - menuBarHeight)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        engine.overlayVisible = true
        hasShownOnce = true
    }

    private func hide() {
        engine.overlayVisible = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }
        let panel = self.panel
        Task {
            try? await Task.sleep(for: .milliseconds(110))
            if !self.detector.isShowing { panel.orderOut(nil) }
        }
    }
}

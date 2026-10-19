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
    /// Kept for the panel's life: a fresh hosting view lays out the whole sheet again on every hold.
    @ObservationIgnored private var host: NSHostingView<ShortcutSheetView>?
    @ObservationIgnored private var presentations = 0

    /// Onboarding step 3 watches this.
    private(set) var hasShownOnce = false

    init(settings: AppSettings, engine: CoachEngine) {
        self.settings = settings
        self.engine = engine
    }

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
            apply(detector.handle(detector.input(for: press)))
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
        let coaching = Set(Stats.coachingNow(state: engine.state, now: Date()).map(\.identity))
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
            dismissHint: hint,
            presentation: presentations
        )
        presentations += 1

        let screen = NudgeController.targetScreen()
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: screen.frame.height - menuBarHeight)
        if let host {
            host.rootView = view
        } else {
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: frame.size)
            panel.contentView = host
            self.host = host
        }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
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

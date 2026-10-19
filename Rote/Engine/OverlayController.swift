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
    /// False in tests: the sheet opens and closes as usual, but no panel goes on screen.
    @ObservationIgnored private let presentsPanel: Bool
    @ObservationIgnored private var detector = HoldDetector()
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private let panel = OverlayPanel()
    /// Kept for the panel's life: a fresh hosting view lays out the whole sheet again on every hold.
    @ObservationIgnored private var host: NSHostingView<ShortcutSheetView>?
    @ObservationIgnored private var presentations = 0
    /// The menus on the sheet while it is up.
    @ObservationIgnored private(set) var presentedTree: MenuTree?
    #if DEBUG
    /// The Debug menu's simulated sheet is up: any key or click closes it.
    @ObservationIgnored private var isSimulated = false
    #endif

    /// Onboarding step 3 watches this.
    private(set) var hasShownOnce = false

    var isShowing: Bool { detector.isShowing }

    init(settings: AppSettings, engine: CoachEngine, presentsPanel: Bool = true) {
        self.settings = settings
        self.engine = engine
        self.presentsPanel = presentsPanel
    }

    func handle(_ event: KeyEventMonitor.Event) {
        #if DEBUG
        if isSimulated {
            if case .flagsChanged = event { return }
            apply(detector.handle(.stickyToggle))
            return
        }
        #endif
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
            apply(detector.handle(input(for: press)))
        case .mouseDown:
            apply(detector.handle(.mouseDown))
        }
    }

    /// ⌃⌥⌘K toggles the sheet only when it is the chosen trigger. With hold-⌘ or hold-⌥ chosen it is
    /// a key press like any other, so ⌃⌥⌘K meant for another app never opens Rote's sheet. Esc and
    /// the hotkey still close a sticky sheet that is up, even one left up by a trigger change.
    private func input(for press: RoteCore.KeyPress) -> HoldDetector.Input {
        let input = detector.input(for: press)
        guard input == .stickyToggle, !detector.isSticky, settings.overlayTrigger != .stickyHotkey else { return input }
        return .keyDown
    }

    /// The frontmost app changed: a sheet on screen still lists the previous app's shortcuts, so it
    /// closes, a sticky one as Esc closes it and a held one as a click does.
    func frontmostAppChanged() {
        guard detector.isShowing else { return }
        apply(detector.handle(detector.isSticky ? .stickyToggle : .mouseDown))
    }

    #if DEBUG
    /// Shows the sheet with `OverlayFixture`'s menus, for screenshots and visual review. It stays up
    /// like a sticky sheet until Esc, any other key, a click or an app switch closes it, and its
    /// footer shows the hint of the trigger in use, as a real sheet would.
    func simulate() {
        guard !detector.isShowing else { return }
        timer?.cancel()
        timer = nil
        guard detector.handle(.stickyToggle) == .show else { return }
        isSimulated = true
        let fixture = OverlayFixture.tree
        present(
            fixture,
            bundleID: fixture.bundleID,
            coaching: OverlayFixture.coaching,
            learned: OverlayFixture.learned,
            hint: dismissHint(sticky: settings.overlayTrigger == .stickyHotkey)
        )
    }
    #endif

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
        present(tree, bundleID: app.bundleID, coaching: coaching, learned: learned, hint: dismissHint(sticky: detector.isSticky))
    }

    /// The footer's dismiss hint: the sticky one, or the release hint for the hold trigger in use.
    private func dismissHint(sticky: Bool) -> String {
        sticky
            ? l("overlay.stickyHint")
            : l("overlay.releaseHint", settings.overlayTrigger == .holdOption ? "⌥" : "⌘")
    }

    /// Puts `tree` on the sheet, with the icon of the app `bundleID` names.
    private func present(_ tree: MenuTree, bundleID: String, coaching: Set<String>, learned: Set<String>, hint: String) {
        presentedTree = tree
        engine.overlayVisible = true
        hasShownOnce = true
        guard presentsPanel else { return }
        let view = ShortcutSheetView(
            tree: tree,
            appIcon: AppInfo.resolve(bundleID).icon,
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
    }

    private func hide() {
        presentedTree = nil
        #if DEBUG
        isSimulated = false
        #endif
        engine.overlayVisible = false
        guard presentsPanel else { return }
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

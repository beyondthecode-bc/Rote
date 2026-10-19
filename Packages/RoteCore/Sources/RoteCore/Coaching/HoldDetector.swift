import Foundation

/// Hold-to-show state machine (spec §7.2). Timing lives in the caller; this decides.
public struct HoldDetector: Sendable, Equatable {
    public enum Input: Sendable, Equatable {
        /// Exactly the trigger modifier is down.
        case triggerHeld
        /// No modifier is down.
        case triggerReleased
        /// Some other modifier combination is down.
        case otherModifierChange
        case keyDown
        case mouseDown
        case timerFired(Int)
        /// The sticky hotkey (or Esc while sticky) was pressed.
        case stickyToggle
    }

    public enum Output: Sendable, Equatable {
        case none
        case armTimer(Int)
        case disarmTimer
        case show
        case hide
    }

    public private(set) var isShowing = false
    public private(set) var isSticky = false
    private var armedToken: Int?
    private var nextToken = 1

    public init() {}

    public mutating func handle(_ input: Input) -> Output {
        switch input {
        case .triggerHeld:
            if isShowing || armedToken != nil { return .none }
            let token = nextToken
            nextToken += 1
            armedToken = token
            return .armTimer(token)

        case .triggerReleased, .otherModifierChange, .mouseDown:
            if isShowing && !isSticky {
                isShowing = false
                return .hide
            }
            if armedToken != nil {
                armedToken = nil
                return .disarmTimer
            }
            return .none

        case .keyDown:
            if isShowing {
                if isSticky { return .none }
                isShowing = false
                return .hide
            }
            if armedToken != nil {
                armedToken = nil
                return .disarmTimer
            }
            return .none

        case .timerFired(let token):
            guard armedToken == token else { return .none }
            armedToken = nil
            isShowing = true
            isSticky = false
            return .show

        case .stickyToggle:
            armedToken = nil
            if isShowing {
                isShowing = false
                isSticky = false
                return .hide
            }
            isShowing = true
            isSticky = true
            return .show
        }
    }
}

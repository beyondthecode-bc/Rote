import ApplicationServices
import Foundation

/// A read that failed for a reason other than "no value": the app is busy, hung or has quit
/// (macOS answers `.cannotComplete` for all three), the element is gone (`.invalidUIElement`),
/// or trust was revoked (`.apiDisabled`). What was read so far is incomplete.
struct AXReadError: Error, Equatable {
    let code: AXError
}

/// Thin, synchronous helpers over `AXUIElementCopy*`. Internal to the package.
///
/// The `read…` forms tell a real absence (no value, unsupported attribute) from a failed read;
/// the Optional forms fold both into nil, `[]` or `[:]` for callers that want best-effort values.
enum AXReader {
    /// Seconds an Accessibility call waits for an app before failing with `.cannotComplete`.
    /// The system default (about 1.5 s on macOS 27) lets one hung app blow the 300 ms scan
    /// budget (spec §5.1) and stall main-actor callers.
    static let messagingTimeout: Float = 0.25

    /// Applies `messagingTimeout` to the whole process, once. Set on the system-wide element it
    /// covers every element, including ones created earlier; a per-element timeout would not reach
    /// that element's children. Every read below calls this; code that messages an app through
    /// other AX calls (observer registration) calls it before its first call.
    static func configure() {
        _ = timeoutApplied
    }

    private static let timeoutApplied: Void = {
        _ = AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
    }()

    /// `.noValue` and `.attributeUnsupported` mean the attribute is absent; every other failure is passed on.
    static func classify(_ code: AXError, _ value: AnyObject?) -> Result<AnyObject?, AXReadError> {
        switch code {
        case .success: .success(value)
        case .noValue, .attributeUnsupported: .success(nil)
        default: .failure(AXReadError(code: code))
        }
    }

    static func read(_ element: AXUIElement, _ attribute: String) -> Result<AnyObject?, AXReadError> {
        configure()
        var out: AnyObject?
        let code = AXUIElementCopyAttributeValue(element, attribute as CFString, &out)
        return classify(code, out)
    }

    static func readElement(_ element: AXUIElement, _ attribute: String) -> Result<AXUIElement?, AXReadError> {
        read(element, attribute).map { raw in
            guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
            return (raw as! AXUIElement)
        }
    }

    static func readElements(_ element: AXUIElement, _ attribute: String) -> Result<[AXUIElement], AXReadError> {
        read(element, attribute).map { raw in
            guard let array = raw as? [AnyObject] else { return [] }
            return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
        }
    }

    /// One IPC round trip for several attributes. Missing values and per-attribute errors are simply
    /// absent from the result; a failed call, or a reply of the wrong length, is a failure.
    static func readMultiple(_ element: AXUIElement, _ attributes: [String]) -> Result<[String: AnyObject], AXReadError> {
        configure()
        var values: CFArray?
        let code = AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, [], &values)
        guard code == .success else { return classify(code, nil).map { _ in [:] } }
        guard let array = values as? [AnyObject], array.count == attributes.count else {
            return .failure(AXReadError(code: .failure))
        }
        var result: [String: AnyObject] = [:]
        for (index, raw) in array.enumerated() {
            let typeID = CFGetTypeID(raw)
            if typeID == CFNullGetTypeID() { continue }
            if typeID == AXValueGetTypeID(), AXValueGetType(raw as! AXValue) == .axError { continue }
            result[attributes[index]] = raw
        }
        return .success(result)
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        try? read(element, attribute).get()
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        try? readElement(element, attribute).get()
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (try? readElements(element, attribute).get()) ?? []
    }

    static func multiple(_ element: AXUIElement, _ attributes: [String]) -> [String: AnyObject] {
        (try? readMultiple(element, attributes).get()) ?? [:]
    }
}

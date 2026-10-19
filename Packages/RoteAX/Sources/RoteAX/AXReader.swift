import ApplicationServices
import Foundation

/// Thin, synchronous helpers over `AXUIElementCopy*`. Internal to the package.
enum AXReader {
    static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var out: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &out)
        return error == .success ? out : nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let raw = value(element, attribute), let array = raw as? [AnyObject] else { return [] }
        return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    /// One IPC round trip for several attributes. Missing values are simply absent from the result.
    static func multiple(_ element: AXUIElement, _ attributes: [String]) -> [String: AnyObject] {
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, [], &values)
        guard error == .success, let array = values as? [AnyObject], array.count == attributes.count else { return [:] }
        var result: [String: AnyObject] = [:]
        for (index, raw) in array.enumerated() {
            let typeID = CFGetTypeID(raw)
            if typeID == CFNullGetTypeID() { continue }
            if typeID == AXValueGetTypeID(), AXValueGetType(raw as! AXValue) == .axError { continue }
            result[attributes[index]] = raw
        }
        return result
    }
}

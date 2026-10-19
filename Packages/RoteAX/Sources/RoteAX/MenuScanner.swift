import ApplicationServices
import Foundation
import RoteCore

public protocol MenuScanning: Sendable {
    func scan(app: AppIdentity) async -> MenuTree
}

/// Walks an app's menu bar through Accessibility off the main thread (spec §5.1).
public actor MenuScanner: MenuScanning {
    private let budget: TimeInterval

    /// - Parameter budget: seconds before the walk stops and the tree is marked partial.
    public init(budget: TimeInterval = 0.3) {
        self.budget = budget
    }

    public func scan(app: AppIdentity) -> MenuTree {
        MenuTreeBuilder.build(snapshot(app: app))
    }

    /// Raw snapshot; also what the Debug "Export menu snapshot" command writes.
    public func snapshot(app: AppIdentity) -> MenuSnapshot {
        let deadline = Date().addingTimeInterval(budget)
        var partial = false
        var barItems: [AXMenuNode] = []
        let application = AXUIElementCreateApplication(app.pid)
        do {
            if let menuBar = try AXReader.readElement(application, kAXMenuBarAttribute).get() {
                for bar in try AXReader.readElements(menuBar, kAXChildrenAttribute).get() {
                    guard !partial, Date() <= deadline else { partial = true; break }
                    barItems.append(node(for: bar, deadline: deadline, partial: &partial))
                }
            }
        } catch {
            partial = true                              // busy, hung or quit (spec §11): never cached as complete
        }
        if Date() > deadline { partial = true }
        return MenuSnapshot(bundleID: app.bundleID, appName: app.name, barItems: barItems, isPartial: partial, takenAt: Date())
    }

    private static let itemAttributes: [String] = [
        kAXRoleAttribute, kAXTitleAttribute, kAXEnabledAttribute,
        kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute,
        kAXMenuItemCmdVirtualKeyAttribute, kAXMenuItemCmdGlyphAttribute,
    ]

    private func node(for element: AXUIElement, deadline: Date, partial: inout Bool) -> AXMenuNode {
        let attributes: [String: AnyObject]
        switch AXReader.readMultiple(element, Self.itemAttributes) {
        case .success(let values):
            attributes = values
        case .failure:
            attributes = [:]
            partial = true
        }
        var result = AXMenuNode(
            role: attributes[kAXRoleAttribute] as? String ?? "",
            title: attributes[kAXTitleAttribute] as? String ?? "",
            isEnabled: (attributes[kAXEnabledAttribute] as? NSNumber)?.boolValue ?? true,
            cmdChar: attributes[kAXMenuItemCmdCharAttribute] as? String,
            cmdModifiers: (attributes[kAXMenuItemCmdModifiersAttribute] as? NSNumber)?.intValue,
            cmdVirtualKey: (attributes[kAXMenuItemCmdVirtualKeyAttribute] as? NSNumber)?.intValue,
            cmdGlyph: (attributes[kAXMenuItemCmdGlyphAttribute] as? NSNumber)?.intValue
        )
        guard !partial, Date() <= deadline else {
            partial = true
            return result
        }
        switch AXReader.readElements(element, kAXChildrenAttribute) {
        case .success(let children):
            for child in children {
                guard !partial, Date() <= deadline else { partial = true; break }
                result.children.append(node(for: child, deadline: deadline, partial: &partial))
            }
        case .failure:
            partial = true
        }
        return result
    }
}

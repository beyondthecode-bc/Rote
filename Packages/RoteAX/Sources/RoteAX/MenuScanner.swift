import ApplicationServices
import Foundation
import RoteCore

public protocol MenuScanning: Sendable {
    func scan(app: AppIdentity) async -> MenuTree
}

/// The Accessibility reads the walk makes. Production reads a live app; tests replay a recorded
/// snapshot with injected failures (spec §14).
protocol MenuElementSource {
    associatedtype Element
    func menuBar() -> Result<Element?, AXReadError>
    func children(of element: Element) -> Result<[Element], AXReadError>
    func attributes(of element: Element, _ names: [String]) -> Result<[String: AnyObject], AXReadError>
}

struct AXMenuElementSource: MenuElementSource {
    let application: AXUIElement

    func menuBar() -> Result<AXUIElement?, AXReadError> {
        AXReader.readElement(application, kAXMenuBarAttribute)
    }

    func children(of element: AXUIElement) -> Result<[AXUIElement], AXReadError> {
        AXReader.readElements(element, kAXChildrenAttribute)
    }

    func attributes(of element: AXUIElement, _ names: [String]) -> Result<[String: AnyObject], AXReadError> {
        AXReader.readMultiple(element, names)
    }
}

/// Walks an app's menu bar through Accessibility off the main thread (spec §5.1).
public actor MenuScanner: MenuScanning {
    /// Levels below a bar item the walk descends. Real menus are bar item › menu › item › menu › item,
    /// five submenus at most; a hostile app answering with a deeper or cyclic `AXChildren` would
    /// otherwise recurse until the 512 KB cooperative-pool stack ran out (audit M3).
    static let maxDepth = 12
    /// Elements read in one walk, over every bar item. Past it the tree is partial.
    static let maxNodes = 5_000

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
        let clock = ContinuousClock()                   // monotonic: a clock change cannot stretch the budget
        let deadline = clock.now.advanced(by: .seconds(budget))
        let source = AXMenuElementSource(application: AXUIElementCreateApplication(app.pid))
        return Self.snapshot(of: source, app: app) { clock.now > deadline }
    }

    /// The walk. Stops at the first failed read, once `isExpired`, past `maxDepth` levels or
    /// `maxNodes` elements, marking the snapshot partial.
    static func snapshot<Source: MenuElementSource>(of source: Source, app: AppIdentity, isExpired: () -> Bool) -> MenuSnapshot {
        var partial = false
        var barItems: [AXMenuNode] = []
        var complete = 0
        var nodes = 0
        do {
            if let menuBar = try source.menuBar().get() {
                for bar in try source.children(of: menuBar).get() {
                    guard !partial, !isExpired() else { partial = true; break }
                    guard nodes < maxNodes else { partial = true; break }
                    barItems.append(node(for: bar, source: source, depth: 0, nodes: &nodes, isExpired: isExpired, partial: &partial))
                    if !partial { complete += 1 }
                }
            }
        } catch {
            partial = true                              // busy, hung or quit (spec §11): never cached as complete
        }
        if isExpired() { partial = true }
        return MenuSnapshot(bundleID: app.bundleID, appName: app.name, barItems: barItems, isPartial: partial, completeBarItemCount: complete, takenAt: Date())
    }

    private static let itemAttributes: [String] = [
        kAXRoleAttribute, kAXTitleAttribute, kAXEnabledAttribute,
        kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute,
        kAXMenuItemCmdVirtualKeyAttribute, kAXMenuItemCmdGlyphAttribute,
    ]

    /// Reads one element. `depth` is 0 for a bar item; `nodes` counts the elements read so far
    /// and the caller checks it before each call, so a node is never read past `maxNodes`.
    private static func node<Source: MenuElementSource>(for element: Source.Element, source: Source, depth: Int, nodes: inout Int, isExpired: () -> Bool, partial: inout Bool) -> AXMenuNode {
        nodes += 1
        let attributes: [String: AnyObject]
        switch source.attributes(of: element, itemAttributes) {
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
        guard !partial, !isExpired() else {
            partial = true
            return result
        }
        guard depth < maxDepth else {
            partial = true                              // deeper than any real menu: not descended
            return result
        }
        switch source.children(of: element) {
        case .success(let children):
            for child in children {
                guard !partial, !isExpired() else { partial = true; break }
                guard nodes < maxNodes else { partial = true; break }
                result.children.append(node(for: child, source: source, depth: depth + 1, nodes: &nodes, isExpired: isExpired, partial: &partial))
            }
        case .failure:
            partial = true
        }
        return result
    }
}

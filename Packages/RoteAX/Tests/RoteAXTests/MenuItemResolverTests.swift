import ApplicationServices
import XCTest
import RoteCore
@testable import RoteAX

/// A recorded Accessibility hierarchy: each element id has its attributes and its parent.
/// The application "app" holds the main menu bar "bar".
private struct RecordedItemSource: MenuItemSource {
    private var values: [String: [String: AnyObject]] = [:]
    private var parents: [String: String] = [:]
    let mainMenuBar = "bar"

    init() {
        add("app", role: "AXApplication", parent: nil)
        add(mainMenuBar, role: "AXMenuBar", parent: "app")
    }

    /// The snapshot's bar items under the main menu bar. Ids are index paths such as "3/0/1".
    init(_ snapshot: MenuSnapshot) {
        self.init()
        for (index, bar) in snapshot.barItems.enumerated() { add(bar, id: "\(index)", parent: mainMenuBar) }
    }

    mutating func add(_ id: String, role: String, title: String? = nil, parent: String?) {
        var attributes: [String: AnyObject] = [kAXRoleAttribute: role as NSString]
        if let title { attributes[kAXTitleAttribute] = title as NSString }
        values[id] = attributes
        parents[id] = parent
    }

    mutating func add(_ node: AXMenuNode, id: String, parent: String) {
        var attributes: [String: AnyObject] = [
            kAXRoleAttribute: node.role as NSString,
            kAXTitleAttribute: node.title as NSString,
            kAXEnabledAttribute: NSNumber(value: node.isEnabled),
        ]
        if let value = node.cmdChar { attributes[kAXMenuItemCmdCharAttribute] = value as NSString }
        if let value = node.cmdModifiers { attributes[kAXMenuItemCmdModifiersAttribute] = NSNumber(value: value) }
        if let value = node.cmdVirtualKey { attributes[kAXMenuItemCmdVirtualKeyAttribute] = NSNumber(value: value) }
        if let value = node.cmdGlyph { attributes[kAXMenuItemCmdGlyphAttribute] = NSNumber(value: value) }
        values[id] = attributes
        parents[id] = parent
        for (index, child) in node.children.enumerated() { add(child, id: "\(id)/\(index)", parent: id) }
    }

    func attributes(of element: String, _ names: [String]) -> [String: AnyObject] {
        (values[element] ?? [:]).filter { names.contains($0.key) }
    }

    func parent(of element: String) -> String? { parents[element] }

    func isMainMenuBar(_ element: String) -> Bool { element == mainMenuBar }
}

final class MenuItemResolverTests: XCTestCase {
    private func fixture() throws -> MenuSnapshot {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "safari-mini", withExtension: "json", subdirectory: "Fixtures"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MenuSnapshot.self, from: Data(contentsOf: url))
    }

    /// Ids of the AXMenuItems without a submenu, in menu order.
    private func leafIDs(_ node: AXMenuNode, id: String) -> [String] {
        if node.role == "AXMenuItem", !node.children.contains(where: { $0.role == "AXMenu" }) { return [id] }
        return node.children.enumerated().flatMap { leafIDs($0.element, id: "\(id)/\($0.offset)") }
    }

    private func resolve(_ id: String, in source: RecordedItemSource) -> MenuItemRecord? {
        MenuItemResolver.record(for: id, source: source, bundleID: "com.apple.Safari")
    }

    /// A selection must land on the record the scan stored, or the coach keys it apart (spec §5.3).
    func testEveryMenuBarItemResolvesToTheScannedRecord() throws {
        let snapshot = try fixture()
        let source = RecordedItemSource(snapshot)
        let ids = snapshot.barItems.enumerated().flatMap { leafIDs($0.element, id: "\($0.offset)") }
        let expected = MenuTreeBuilder.build(snapshot).menus.flatMap(\.items)
        XCTAssertTrue(expected.contains { $0.path == ["Edit", "Find", "Find Next"] }, "the fixture covers submenus")
        XCTAssertEqual(ids.compactMap { resolve($0, in: source) }, expected)
    }

    /// Spec §2: pop-up buttons and context menus are not coached.
    func testItemsOutsideTheMenuBarResolveToNothing() {
        var source = RecordedItemSource()
        source.add("window", role: "AXWindow", title: "Untitled", parent: "app")
        source.add("popUp", role: "AXPopUpButton", title: "Alpha", parent: "window")
        source.add("popUpMenu", role: "AXMenu", parent: "popUp")
        source.add(AXMenuNode(role: "AXMenuItem", title: "Beta", isEnabled: true, cmdChar: "B", cmdModifiers: 0), id: "beta", parent: "popUpMenu")
        source.add("contextMenu", role: "AXMenu", parent: "app")
        source.add(AXMenuNode(role: "AXMenuItem", title: "Copy", isEnabled: true, cmdChar: "C", cmdModifiers: 0), id: "copy", parent: "contextMenu")
        XCTAssertNil(resolve("beta", in: source))
        XCTAssertNil(resolve("copy", in: source))
    }

    /// A status-item menu hangs off the app's extras bar, also an AXMenuBar, under an untitled bar item.
    func testStatusItemMenusResolveToNothing() {
        var source = RecordedItemSource()
        source.add("extras", role: "AXMenuBar", parent: "app")
        source.add("statusItem", role: "AXMenuBarItem", title: "", parent: "extras")
        source.add("statusMenu", role: "AXMenu", parent: "statusItem")
        source.add(AXMenuNode(role: "AXMenuItem", title: "Settings…", isEnabled: true, cmdChar: ",", cmdModifiers: 0), id: "settings", parent: "statusMenu")
        XCTAssertNil(resolve("settings", in: source))
    }

    func testOnlyMenuItemsResolve() throws {
        var source = RecordedItemSource(try fixture())
        source.add("label", role: "AXStaticText", title: "Label", parent: "2/0")   // inside File
        XCTAssertNil(resolve("label", in: source))
        XCTAssertNil(resolve("2", in: source), "a bar item is not an item")
        XCTAssertNil(resolve("1/0/1", in: source), "a separator has no title")
    }

    func testAnItemThatReportsNoEnabledStateIsEnabled() throws {
        var source = RecordedItemSource(try fixture())
        source.add("plain", role: "AXMenuItem", title: "Plain", parent: "2/0")
        let record = try XCTUnwrap(resolve("plain", in: source))
        XCTAssertEqual(record.path, ["File", "Plain"])
        XCTAssertTrue(record.isEnabled)
    }

    func testDisabledItemKeepsItsStateAndShortcut() throws {
        let source = RecordedItemSource(try fixture())
        let record = try XCTUnwrap(resolve("2/0/2", in: source))
        XCTAssertEqual(record.identity, "com.apple.Safari|File›Close Tab")
        XCTAssertFalse(record.isEnabled)
        XCTAssertNotNil(record.shortcut)
    }
}

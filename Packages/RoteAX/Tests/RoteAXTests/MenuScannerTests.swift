import ApplicationServices
import XCTest
import RoteCore
@testable import RoteAX

/// Replays a recorded snapshot through the scanner's walk. Elements are index paths into the
/// recorded bar items (the menu bar is `[]`); listed paths fail the way a busy app does.
private final class RecordedMenuSource: MenuElementSource {
    let barItems: [AXMenuNode]?
    var failMenuBar = false
    var failingChildren: Set<[Int]> = []
    var failingAttributes: Set<[Int]> = []
    private(set) var attributeReads = 0

    init(_ snapshot: MenuSnapshot?) {
        barItems = snapshot?.barItems
    }

    private var busy: AXReadError { AXReadError(code: .cannotComplete) }

    private func node(at path: [Int]) -> AXMenuNode {
        var node = barItems![path[0]]
        for index in path.dropFirst() { node = node.children[index] }
        return node
    }

    func menuBar() -> Result<[Int]?, AXReadError> {
        if failMenuBar { return .failure(busy) }
        return .success(barItems == nil ? nil : [])
    }

    func children(of element: [Int]) -> Result<[[Int]], AXReadError> {
        if failingChildren.contains(element) { return .failure(busy) }
        let count = element.isEmpty ? barItems!.count : node(at: element).children.count
        return .success((0..<count).map { element + [$0] })
    }

    func attributes(of element: [Int], _ names: [String]) -> Result<[String: AnyObject], AXReadError> {
        attributeReads += 1
        if failingAttributes.contains(element) { return .failure(busy) }
        let node = node(at: element)
        var values: [String: AnyObject] = [
            kAXRoleAttribute: node.role as NSString,
            kAXTitleAttribute: node.title as NSString,
            kAXEnabledAttribute: NSNumber(value: node.isEnabled),
        ]
        if let value = node.cmdChar { values[kAXMenuItemCmdCharAttribute] = value as NSString }
        if let value = node.cmdModifiers { values[kAXMenuItemCmdModifiersAttribute] = NSNumber(value: value) }
        if let value = node.cmdVirtualKey { values[kAXMenuItemCmdVirtualKeyAttribute] = NSNumber(value: value) }
        if let value = node.cmdGlyph { values[kAXMenuItemCmdGlyphAttribute] = NSNumber(value: value) }
        return .success(values.filter { names.contains($0.key) })
    }
}

final class MenuScannerTests: XCTestCase {
    private let safari = AppIdentity(pid: 1, bundleID: "com.apple.Safari", name: "Safari")

    private func fixture() throws -> MenuSnapshot {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "safari-mini", withExtension: "json", subdirectory: "Fixtures"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MenuSnapshot.self, from: Data(contentsOf: url))
    }

    private func walk(_ source: RecordedMenuSource, expired: () -> Bool = { false }) -> MenuSnapshot {
        MenuScanner.snapshot(of: source, app: safari, isExpired: expired)
    }

    func testWalkReadsTheWholeTree() throws {
        let recorded = try fixture()
        let snapshot = walk(RecordedMenuSource(recorded))
        XCTAssertEqual(snapshot.barItems, recorded.barItems)
        XCTAssertFalse(snapshot.isPartial)
        XCTAssertEqual(snapshot.completeBarItemCount, recorded.barItems.count)
        XCTAssertEqual(snapshot.bundleID, "com.apple.Safari")
        XCTAssertEqual(snapshot.appName, "Safari")
    }

    /// A busy app fails a read halfway through File (spec §11): the walk stops there, the tree is
    /// partial, and only Apple and Safari count as read in full, so a cached File is kept.
    func testFailedChildrenReadStopsTheWalkInsideAMenu() throws {
        let source = RecordedMenuSource(try fixture())
        source.failingChildren = [[2, 0]]
        let snapshot = walk(source)
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertEqual(snapshot.barItems.map(\.title), ["Apple", "Safari", "File"])
        XCTAssertEqual(snapshot.completeBarItemCount, 2)
        let tree = MenuTreeBuilder.build(snapshot)
        XCTAssertEqual(tree.menus.map(\.isComplete), [true, true, false])
        XCTAssertTrue(tree.menus[2].items.isEmpty)
    }

    func testFailedAttributeReadStopsTheWalk() throws {
        let source = RecordedMenuSource(try fixture())
        source.failingAttributes = [[3, 0, 1]]
        let snapshot = walk(source)
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertEqual(snapshot.barItems.count, 4)
        XCTAssertEqual(snapshot.completeBarItemCount, 3)
    }

    func testUnreadableMenuBarIsPartialAndEmpty() throws {
        let source = RecordedMenuSource(try fixture())
        source.failMenuBar = true
        let snapshot = walk(source)
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertTrue(snapshot.barItems.isEmpty)
        XCTAssertEqual(snapshot.completeBarItemCount, 0)
    }

    func testUnreadableBarItemListIsPartialAndEmpty() throws {
        let source = RecordedMenuSource(try fixture())
        source.failingChildren = [[]]
        let snapshot = walk(source)
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertTrue(snapshot.barItems.isEmpty)
    }

    func testAppWithoutMenuBarIsEmptyNotPartial() {
        let snapshot = walk(RecordedMenuSource(nil))
        XCTAssertFalse(snapshot.isPartial)
        XCTAssertTrue(snapshot.barItems.isEmpty)
        XCTAssertEqual(snapshot.completeBarItemCount, 0)
    }

    func testBudgetStopsTheWalk() throws {
        let recorded = try fixture()
        let source = RecordedMenuSource(recorded)
        let snapshot = walk(source) { source.attributeReads >= 12 }
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertLessThanOrEqual(source.attributeReads, 12)
        XCTAssertLessThan(snapshot.completeBarItemCount, recorded.barItems.count)
        XCTAssertLessThanOrEqual(snapshot.completeBarItemCount, snapshot.barItems.count)
    }

    /// No live trust needed: a pid above PID_MAX fails with `.cannotComplete` when trusted and
    /// `.apiDisabled` when not, and either must read as partial, never as an empty menu bar.
    func testUnreachableAppIsPartial() async {
        let gone = AppIdentity(pid: 999_999, bundleID: "com.example.gone", name: "Gone")
        let snapshot = await MenuScanner().snapshot(app: gone)
        XCTAssertTrue(snapshot.barItems.isEmpty)
        XCTAssertTrue(snapshot.isPartial)
    }
}

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
    /// Elements whose only child is themselves: an `AXChildren` cycle a hostile app can answer with.
    var cyclicElements: Set<[Int]> = []
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
        if cyclicElements.contains(element) { return .success([element]) }
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

    // MARK: Hostile trees (audit M3)

    /// `levels` menus nested in one bar item, each holding one item that opens the next.
    static func nested(levels: Int) -> MenuSnapshot {
        var node = AXMenuNode(role: "AXMenuItem", title: "Deepest", isEnabled: true, cmdChar: "D", cmdModifiers: 0)
        for level in stride(from: levels, to: 0, by: -1) {
            let menu = AXMenuNode(role: "AXMenu", title: "", isEnabled: true, children: [node])
            node = AXMenuNode(role: "AXMenuItem", title: "Level \(level)", isEnabled: true, children: [menu])
        }
        let bar = AXMenuNode(role: "AXMenuBarItem", title: "Deep", isEnabled: true, children: [AXMenuNode(role: "AXMenu", title: "", isEnabled: true, children: [node])])
        return MenuSnapshot(bundleID: "com.example.deep", appName: "Deep", barItems: [bar], isPartial: false, completeBarItemCount: 1, takenAt: Date())
    }

    /// One menu with `count` items.
    static func flat(count: Int) -> MenuSnapshot {
        let items = (0..<count).map { AXMenuNode(role: "AXMenuItem", title: "Item \($0)", isEnabled: true, cmdChar: "A", cmdModifiers: 0) }
        let bar = AXMenuNode(role: "AXMenuBarItem", title: "Wide", isEnabled: true, children: [AXMenuNode(role: "AXMenu", title: "", isEnabled: true, children: items)])
        return MenuSnapshot(bundleID: "com.example.wide", appName: "Wide", barItems: [bar], isPartial: false, completeBarItemCount: 1, takenAt: Date())
    }

    static func depth(_ node: AXMenuNode) -> Int { 1 + (node.children.map(depth).max() ?? 0) }
    static func count(_ node: AXMenuNode) -> Int { 1 + node.children.map(count).reduce(0, +) }

    func testDeeplyNestedTreeStopsAtTheDepthCap() {
        let source = RecordedMenuSource(Self.nested(levels: 40))
        let snapshot = walk(source)
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertEqual(snapshot.completeBarItemCount, 0)
        XCTAssertEqual(snapshot.barItems.count, 1)
        XCTAssertEqual(Self.depth(snapshot.barItems[0]), MenuScanner.maxDepth + 1, "nodes down to the cap are read; the cap is counted from the bar item")
        XCTAssertLessThanOrEqual(source.attributeReads, MenuScanner.maxDepth + 1)
    }

    func testRealisticNestingIsReadInFull() {
        let source = RecordedMenuSource(Self.nested(levels: 4))
        let snapshot = walk(source)
        XCTAssertFalse(snapshot.isPartial)
        XCTAssertEqual(Self.depth(snapshot.barItems[0]), 11)
    }

    /// An app whose `AXChildren` answers point back at the element: without a cap the walk never ends.
    func testCyclicTreeStopsAtTheDepthCap() throws {
        let source = RecordedMenuSource(try fixture())
        source.cyclicElements = [[0, 0]]                      // the Apple menu's AXMenu is its own child
        let snapshot = walk(source)
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertEqual(Self.depth(snapshot.barItems[0]), MenuScanner.maxDepth + 1)
        XCTAssertLessThanOrEqual(source.attributeReads, MenuScanner.maxDepth + 1)
        XCTAssertEqual(snapshot.completeBarItemCount, 0)
    }

    func testNodeCapStopsTheWalk() {
        let source = RecordedMenuSource(Self.flat(count: MenuScanner.maxNodes + 1_000))
        let snapshot = walk(source)
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertEqual(Self.count(snapshot.barItems[0]), MenuScanner.maxNodes)
        XCTAssertEqual(source.attributeReads, MenuScanner.maxNodes)
        let wide = RecordedMenuSource(Self.flat(count: MenuScanner.maxNodes - 2))
        XCTAssertFalse(walk(wide).isPartial, "a tree at the cap is complete")
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

import XCTest
@testable import RoteCore

final class MenuItemIdentityTests: XCTestCase {
    func testQuotedSubstringsAreStripped() {
        XCTAssertEqual(MenuItemIdentity.normalize("Close Tab “Example”"), "Close Tab")
        XCTAssertEqual(MenuItemIdentity.normalize("Close Tab \"Example\""), "Close Tab")
        XCTAssertEqual(MenuItemIdentity.normalize("Open ‘Notes’ in New Window"), "Open in New Window")
    }

    func testWhitespaceCollapses() {
        XCTAssertEqual(MenuItemIdentity.normalize("  Save   As…  "), "Save As…")
    }

    func testEllipsisIsKept() {
        XCTAssertEqual(MenuItemIdentity.normalize("Print…"), "Print…")
    }

    func testSingleApostropheSurvives() {
        XCTAssertEqual(MenuItemIdentity.normalize("Don't Save"), "Don't Save")
    }

    func testApostrophesAreNeverQuotes() {
        XCTAssertEqual(MenuItemIdentity.normalize("Can't Undo Today's Edit"), "Can't Undo Today's Edit")
    }

    func testFullyQuotedTitlesKeepTheirRawTitle() {
        let a = MenuItemIdentity.make(bundleID: "a", path: ["File", "Open Recent", "“Doc A”"])
        let b = MenuItemIdentity.make(bundleID: "a", path: ["File", "Open Recent", "“Doc B”"])
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, "a|File›Open Recent›“Doc A”")
    }

    func testIdentityIsDerivedNotPersisted() throws {
        let json = #"{"bundleID":"com.apple.Safari","path":["View","Reload Page “Now”"],"shortcut":null}"#
        let record = try JSONDecoder().decode(MenuItemRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.identity, "com.apple.Safari|View›Reload Page")
        XCTAssertTrue(record.isEnabled, "isEnabled defaults to true when absent")
        XCTAssertFalse(record.hasUnrenderableShortcut)
        let encoded = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        XCTAssertFalse(encoded.contains("identity"), "identity must not be written to disk")
    }

    func testTypographicApostropheSurvives() {
        XCTAssertEqual(MenuItemIdentity.normalize("Can’t Undo"), "Can’t Undo")
        XCTAssertEqual(MenuItemIdentity.normalize("Open ‘Today’s Notes’"), "Open")
    }

    func testLocalizedQuotePairs() {
        XCTAssertEqual(MenuItemIdentity.normalize("Datenträger „Backup“ löschen"), "Datenträger löschen")
        XCTAssertEqual(MenuItemIdentity.normalize("Effacer « Sauvegarde »"), "Effacer")
        XCTAssertEqual(MenuItemIdentity.normalize("Radera skivan ”Backup”"), "Radera skivan")
        XCTAssertEqual(MenuItemIdentity.normalize("ファイル“テスト”を開く"), "ファイルを開く")
        XCTAssertEqual(MenuItemIdentity.normalize("打开「测试」"), "打开")
    }

    func testUnbalancedAndNestedQuotes() {
        XCTAssertEqual(MenuItemIdentity.normalize("Open “Unfinished"), "Open “Unfinished")
        XCTAssertEqual(MenuItemIdentity.normalize("Show “Outer ‘inner’ outer” Now"), "Show Now")
    }

    func testStaleIdentityKeyInJSONIsIgnored() throws {
        let json = #"{"bundleID":"a","path":["File","Save"],"identity":"stale|value","hasUnrenderableShortcut":false,"isEnabled":true}"#
        let record = try JSONDecoder().decode(MenuItemRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.identity, "a|File›Save")
    }

    func testIdentityCombinesBundleAndPath() {
        let id = MenuItemIdentity.make(bundleID: "com.apple.Safari", path: ["File", "Close Tab “Example”"])
        XCTAssertEqual(id, "com.apple.Safari|File›Close Tab")
    }

    func testRecordDerivedProperties() {
        let record = MenuItemRecord(
            bundleID: "com.apple.Safari",
            path: ["Edit", "Find", "Find Next"],
            shortcut: Shortcut(modifiers: [.command], key: .character("G"))
        )
        XCTAssertEqual(record.title, "Find Next")
        XCTAssertEqual(record.menuTitle, "Edit")
        XCTAssertEqual(record.parentPath, ["Find"])
        XCTAssertEqual(record.identity, "com.apple.Safari|Edit›Find›Find Next")
        XCTAssertTrue(record.isCoachable)
    }

    func testDisabledOrShortcutlessIsNotCoachable() {
        var record = MenuItemRecord(bundleID: "a", path: ["File", "Save"], shortcut: nil)
        XCTAssertFalse(record.isCoachable)
        record.shortcut = Shortcut(modifiers: [.command], key: .character("S"))
        record.isEnabled = false
        XCTAssertFalse(record.isCoachable)
    }
}

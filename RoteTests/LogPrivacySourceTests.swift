import XCTest
@testable import Rote

/// Reads the app's sources and PRIVACY.md: what the unified log receives in plain text is a
/// privacy promise, and no test that runs the engine can see a `privacy:` argument (audit M2).
final class LogPrivacySourceTests: XCTestCase {
    private static var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func appSources() throws -> [(name: String, text: String)] {
        let root = Self.repository.appendingPathComponent("Rote", isDirectory: true)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 10, "the app's sources were not found at \(root.path)")
        return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// Menu titles can name documents, volumes and mailboxes; every admin can read the log and
    /// sysdiagnose collects it.
    func testTheNudgedItemIsLoggedPrivately() throws {
        let engine = try XCTUnwrap(try appSources().first { $0.name == "CoachEngine.swift" }).text
        XCTAssertTrue(engine.contains(#""Nudge: \(record.item.title, privacy: .private)""#))
        XCTAssertFalse(engine.contains(#"record.item.title, privacy: .public"#))
    }

    /// No log line puts a title, path or identity of a menu item into the log in plain text.
    func testNoMenuItemTextIsLoggedPublicly() throws {
        let publicItemText = #/\\\((?:[^()]|\([^()]*\))*?(?:item\.(?:title|path)|record\.(?:title|path)|\.identity|parentPath|menuTitle)(?:[^()]|\([^()]*\))*?privacy:\s*\.public\)/#
        for (name, text) in try appSources() {
            for match in text.matches(of: publicItemText) {
                XCTFail("\(name): \(match.output) logs menu item text publicly")
            }
        }
    }

    /// A bundle identifier names an app the user runs. It appears in plain text only at debug level,
    /// which the log does not persist.
    func testBundleIDsArePublicOnlyAtDebugLevel() throws {
        var checked = 0
        for (name, text) in try appSources() {
            for line in text.split(separator: "\n") where line.contains("bundleID, privacy: .public") || line.contains("bundleIdentifier, privacy: .public") {
                checked += 1
                XCTAssertTrue(line.contains(".debug("), "\(name): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertGreaterThan(checked, 0, "the scan log line still names the bundle ID at debug level")
    }

    func testPrivacyPolicyDescribesWhatATitleCanHold() throws {
        let policy = try String(contentsOf: Self.repository.appendingPathComponent("PRIVACY.md"), encoding: .utf8)
        for phrase in ["document, volume or mailbox name", "first time you pick", "refreshed each time you use", "marked private"] {
            XCTAssertTrue(policy.contains(phrase), "PRIVACY.md lacks: \(phrase)")
        }
    }
}

import XCTest
@testable import Rote

/// Reads the app's Swift sources, because these mistakes compile and pass every test that calls
/// `LocalizationManager` directly: a key the English table lacks, or a plural phrase called
/// without `count:`, shows the raw key, and a shortcut spoken without `spokenShortcut` is English.
@MainActor
final class LocalizedSourceTests: XCTestCase {
    private static var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Rote", isDirectory: true)
    }

    /// Each Swift file of the app: its name and its text.
    private func sources() throws -> [(name: String, text: String)] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: Self.appSources, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 10, "the app's sources were not found at \(Self.appSources.path)")
        return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    func testEveryKeyTheAppCallsHasEnglishTextInTheFormItIsCalledWith() throws {
        let testDefaults = TestDefaults()
        addTeardownBlock { testDefaults.remove() }
        testDefaults.defaults.set("en", forKey: "rote.language")
        let english = LocalizationManager(defaults: testDefaults.defaults, bundle: .main).strings
        // `l("key"`, then `, count: <expression>` when the call picks a plural form.
        let call = #/(?:^|[^\w.])l\(\s*"(?<key>[^"\\]+)"(?:\s*,\s*count:\s*(?<counted>[^,)]+))?/#.anchorsMatchLineEndings()

        var plain = 0
        var plural = 0
        for (name, text) in try sources() {
            for match in text.matches(of: call) {
                let key = String(match.output.key)
                guard let counted = match.output.counted?.trimmingCharacters(in: .whitespaces) else {
                    plain += 1
                    XCTAssertNotNil(english[key], "\(name): l(\"\(key)\") shows its key (a plural phrase needs count:)")
                    continue
                }
                plural += 1
                XCTAssertNotNil(english[key + ".one"], "\(name): \(key).one")
                XCTAssertNotNil(english[key + ".other"], "\(name): \(key).other")
                // The number the phrase shows is the one that picks its form.
                let rest = text[match.range.upperBound...].prefix { $0 != "\n" }
                if rest.contains("number(") {
                    XCTAssertTrue(rest.contains("number(\(counted))"), "\(name): \(key) takes its form from \(counted) but shows another number")
                }
            }
        }
        XCTAssertGreaterThan(plain, 80, "the calls were found, so the check is not vacuous")
        XCTAssertGreaterThanOrEqual(plural, 8)
    }

    /// A text that names System Settings' list of apps with Accessibility access picks its key
    /// through `PermissionPane.key`, so English needs the key and its macOS 27 form, and every
    /// macOS 27 form is one the app asks for.
    func testEveryKeyThatNamesThePermissionPaneHasItsMacOS27Form() throws {
        let testDefaults = TestDefaults()
        addTeardownBlock { testDefaults.remove() }
        testDefaults.defaults.set("en", forKey: "rote.language")
        let english = LocalizationManager(defaults: testDefaults.defaults, bundle: .main).strings
        let call = #/PermissionPane\.key\(\s*"(?<key>[^"\\]+)"/#

        var called: Set<String> = []
        for (name, text) in try sources() {
            for match in text.matches(of: call) {
                let key = String(match.output.key)
                called.insert(key)
                XCTAssertNotNil(english[key], "\(name): \(key)")
                XCTAssertNotNil(english[key + ".macOS27"], "\(name): \(key).macOS27")
            }
        }
        XCTAssertEqual(called, ["permission.waiting", "onboarding.needsAccess"])
        let macOS27Forms = Set(english.keys.filter { $0.hasSuffix(".macOS27") })
        XCTAssertEqual(macOS27Forms, Set(called.map { $0 + ".macOS27" }))
    }

    func testShortcutsAreSpokenOnlyThroughTheTranslatedKeyNames() throws {
        let english = "GlyphFormatter.spokenDescription"
        let uses = try sources().flatMap { file in
            Array(repeating: file.name, count: file.text.components(separatedBy: english).count - 1)
        }
        XCTAssertEqual(uses, ["KeycapView.swift"], "RoteCore's English names are only spokenShortcut's fallback")
    }
}

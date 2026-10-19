import XCTest

/// The Debug menu's "Simulate overlay" command and its fixture are compiled into Debug builds only:
/// every line of the app's sources that names them sits inside an `#if DEBUG` block. A Release build
/// (`xcodebuild -configuration Release`) is the end-to-end check; this one runs with every test pass.
final class DebugOnlySourceTests: XCTestCase {
    private static let markers = ["Simulate overlay", "simulateOverlay", "OverlayFixture", "isSimulated", "func simulate("]

    private static var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Rote", isDirectory: true)
    }

    func testTheSimulateOverlayCommandIsCompiledIntoDebugBuildsOnly() throws {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: Self.appSources, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 10, "the app's sources were not found at \(Self.appSources.path)")

        var found = Set<String>()
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, debugOnly) in Self.debugOnly(lines).enumerated() {
                for marker in Self.markers where lines[index].contains(marker) {
                    found.insert(marker)
                    XCTAssertTrue(debugOnly, "\(file.lastPathComponent):\(index + 1) names \(marker) outside #if DEBUG")
                }
            }
        }
        XCTAssertEqual(found, Set(Self.markers), "every marker is still in the sources, so the check is not vacuous")
    }

    func testTheConditionalCompilationReaderFollowsNestingAndElse() {
        let lines = [
            "a",
            "#if DEBUG",
            "b",
            "#if os(macOS)",
            "c",
            "#else",
            "d",
            "#endif",
            "#else",
            "e",
            "#endif",
            "#if canImport(AppKit)",
            "f",
            "#elseif DEBUG",
            "g",
            "#endif",
            "#if DEBUG // a comment",
            "h",
            "#endif",
        ]
        let debugOnly = Self.debugOnly(lines)
        let expected = ["a": false, "b": true, "c": true, "d": true, "e": false, "f": false, "g": false, "h": true]
        for (index, line) in lines.enumerated() where expected[line] != nil {
            XCTAssertEqual(debugOnly[index], expected[line], line)
        }
    }

    /// For each line, whether it is compiled only when DEBUG is set. Any branch but a plain
    /// `#if DEBUG` counts as not DEBUG-only, which errs towards failing the check.
    static func debugOnly(_ lines: [String]) -> [Bool] {
        var branches: [Bool] = []       // per open #if: whether its current branch needs DEBUG
        return lines.map { raw in
            let tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
            switch tokens.first {
            case "#if":
                let isDebug = tokens.count >= 2 && tokens[1] == "DEBUG" && (tokens.count == 2 || tokens[2].hasPrefix("//"))
                branches.append(isDebug)
                return branches.contains(true)
            case "#elseif", "#else":
                if !branches.isEmpty { branches[branches.count - 1] = false }
                return branches.contains(true)
            case "#endif":
                let inside = branches.contains(true)
                if !branches.isEmpty { branches.removeLast() }
                return inside
            default:
                return branches.contains(true)
            }
        }
    }
}

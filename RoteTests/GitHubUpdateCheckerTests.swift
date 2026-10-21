import Security
import XCTest
@testable import Rote

/// The pure parts of the updater: what it accepts from the release JSON, the checksum file and
/// the archive, and the fixed text of the privileged step. The network and the swap itself are
/// not exercised here.
final class GitHubUpdateCheckerTests: XCTestCase {
    private typealias Checker = GitHubUpdateChecker

    // MARK: Tags and versions

    func testOnlyAThreePartTagWithAVPrefixIsAVersion() {
        XCTAssertEqual(Checker.version(fromTag: "v1.0.2"), "1.0.2")
        XCTAssertEqual(Checker.version(fromTag: "v10.20.30"), "10.20.30")
        for tag in ["1.0.2", "v1.0", "v1.0.2.1", "v1.0.2-beta", "v1.0.2 ", " v1.0.2", "V1.0.2", "v1.0.x", "", "v1.0.2\n"] {
            XCTAssertNil(Checker.version(fromTag: tag), tag)
        }
    }

    func testNewerComparesNumerically() {
        XCTAssertTrue(Checker.isNewer("1.0.2", than: "1.0.1"))
        XCTAssertTrue(Checker.isNewer("1.10.0", than: "1.9.9"))
        XCTAssertTrue(Checker.isNewer("2.0.0", than: "1.99.99"))
        XCTAssertFalse(Checker.isNewer("1.0.1", than: "1.0.1"))
        XCTAssertFalse(Checker.isNewer("1.0.0", than: "1.0.1"))
        XCTAssertFalse(Checker.isNewer("1.0", than: "1.0.0"), "a missing part is zero")
    }

    // MARK: Release JSON

    private func release(tag: String, assets: [(String, String)], page: String? = "https://github.com/beyondthecode-bc/Rote/releases/tag/v9.9.9") -> [String: Any] {
        var json: [String: Any] = [
            "tag_name": tag,
            "assets": assets.map { ["name": $0.0, "browser_download_url": $0.1] },
        ]
        if let page { json["html_url"] = page }
        return json
    }

    private let zip = "https://github.com/beyondthecode-bc/Rote/releases/download/v1.0.2/Rote-v1.0.2.zip"
    private let sum = "https://github.com/beyondthecode-bc/Rote/releases/download/v1.0.2/Rote-v1.0.2.zip.sha256"

    func testTheReleaseWithBothPinnedAssetsIsADownload() throws {
        let json = release(tag: "v1.0.2", assets: [("Rote-v1.0.2.zip.sha256", sum), ("Source code.zip", "https://github.com/x/y.zip"), ("Rote-v1.0.2.zip", zip)])
        let expected = Checker.ReleaseDownload(version: "1.0.2", zipURL: URL(string: zip)!, checksumURL: URL(string: sum)!)
        XCTAssertEqual(try Checker.release(from: json, currentVersion: "1.0.1"),
                       .available(Checker.AvailableUpdate(version: "1.0.2", source: .download(expected))))
    }

    func testAnOlderOrEqualTagIsUpToDate() throws {
        XCTAssertEqual(try Checker.release(from: release(tag: "v1.0.1", assets: [("Rote-v1.0.1.zip", zip)]), currentVersion: "1.0.1"), .upToDate)
        XCTAssertEqual(try Checker.release(from: release(tag: "v0.9.9", assets: []), currentVersion: "1.0.1"), .upToDate)
    }

    func testATagThatIsNotAVersionIsAnInvalidResponse() {
        for tag in ["1.0.2", "v1.0.2-rc1", "latest"] {
            XCTAssertThrowsError(try Checker.release(from: release(tag: tag, assets: [("Rote-v1.0.2.zip", zip)]), currentVersion: "1.0.1"), tag) { error in
                XCTAssertEqual(error as? Checker.UpdateError, .invalidResponse)
            }
        }
        XCTAssertThrowsError(try Checker.release(from: ["assets": []], currentVersion: "1.0.1"))
    }

    func testAReleaseWithoutThePinnedPairOpensItsPage() throws {
        let page = Checker.AvailableUpdate(version: "1.0.2", source: .page(URL(string: "https://github.com/beyondthecode-bc/Rote/releases/tag/v9.9.9")!))
        // No checksum asset.
        XCTAssertEqual(try Checker.release(from: release(tag: "v1.0.2", assets: [("Rote-v1.0.2.zip", zip)]), currentVersion: "1.0.1"), .available(page))
        // A zip under another name, however close.
        for name in ["Rote.zip", "rote-v1.0.2.zip", "Rote-v1.0.2.zip ", "Rote-1.0.2.zip", "Rote-v1.0.3.zip", "Rote-v1.0.2.zip.zip"] {
            XCTAssertEqual(try Checker.release(from: release(tag: "v1.0.2", assets: [(name, zip), ("Rote-v1.0.2.zip.sha256", sum)]), currentVersion: "1.0.1"), .available(page), name)
        }
        // The right names served from somewhere else, or not over HTTPS.
        for url in ["http://github.com/beyondthecode-bc/Rote/releases/download/v1.0.2/Rote-v1.0.2.zip", "https://example.com/Rote-v1.0.2.zip", "https://github.com.example.com/Rote-v1.0.2.zip", "file:///tmp/Rote-v1.0.2.zip"] {
            XCTAssertEqual(try Checker.release(from: release(tag: "v1.0.2", assets: [("Rote-v1.0.2.zip", url), ("Rote-v1.0.2.zip.sha256", sum)]), currentVersion: "1.0.1"), .available(page), url)
            XCTAssertEqual(try Checker.release(from: release(tag: "v1.0.2", assets: [("Rote-v1.0.2.zip", zip), ("Rote-v1.0.2.zip.sha256", url)]), currentVersion: "1.0.1"), .available(page), url)
        }
    }

    func testThePageItselfMustBeGitHubOverHTTPS() {
        for page in ["http://github.com/beyondthecode-bc/Rote/releases/tag/v1.0.2", "https://example.com/release", nil] {
            XCTAssertThrowsError(try Checker.release(from: release(tag: "v1.0.2", assets: [], page: page), currentVersion: "1.0.1"), page ?? "no page") { error in
                XCTAssertEqual(error as? Checker.UpdateError, .noDownloadAsset)
            }
        }
    }

    // MARK: Checksum

    func testTheChecksumFileIsAShasumLineForTheAsset() {
        let digest = "1e21c1f9b17b95de87674fec1d67ba493f7ee7d850e000a7988c633d1a5f36f9"
        XCTAssertEqual(Checker.expectedDigest(inChecksumFile: "\(digest)  Rote-v1.0.1.zip\n", assetName: "Rote-v1.0.1.zip"), digest)
        XCTAssertEqual(Checker.expectedDigest(inChecksumFile: "\(digest) *Rote-v1.0.1.zip", assetName: "Rote-v1.0.1.zip"), digest, "shasum's binary marker")
        XCTAssertEqual(Checker.expectedDigest(inChecksumFile: digest.uppercased(), assetName: "Rote-v1.0.1.zip"), digest, "a bare digest, lowercased")
        XCTAssertNil(Checker.expectedDigest(inChecksumFile: "\(digest)  Rote-v1.0.2.zip", assetName: "Rote-v1.0.1.zip"), "names another file")
        XCTAssertNil(Checker.expectedDigest(inChecksumFile: String(digest.dropLast()), assetName: "Rote-v1.0.1.zip"), "63 characters")
        XCTAssertNil(Checker.expectedDigest(inChecksumFile: digest.replacingOccurrences(of: "1", with: "g"), assetName: "Rote-v1.0.1.zip"), "not hex")
        XCTAssertNil(Checker.expectedDigest(inChecksumFile: "\(digest)  Rote-v1.0.1.zip  extra", assetName: "Rote-v1.0.1.zip"), "three fields")
        XCTAssertNil(Checker.expectedDigest(inChecksumFile: "", assetName: "Rote-v1.0.1.zip"))
        XCTAssertNil(Checker.expectedDigest(inChecksumFile: "<html>not found</html>", assetName: "Rote-v1.0.1.zip"))
    }

    func testTheFileDigestIsSHA256() throws {
        let directory = try TemporaryDirectory()
        addTeardownBlock { directory.remove() }
        let file = directory.url.appendingPathComponent("abc.bin")
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try Checker.sha256Hex(ofFileAt: file), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        // Larger than one read.
        let big = directory.url.appendingPathComponent("big.bin")
        try Data(repeating: 0x61, count: 3 * 1024 * 1024 + 7).write(to: big)
        XCTAssertEqual(try Checker.sha256Hex(ofFileAt: big), try Checker.sha256Hex(ofFileAt: big))
        XCTAssertNotEqual(try Checker.sha256Hex(ofFileAt: big), try Checker.sha256Hex(ofFileAt: file))
        XCTAssertThrowsError(try Checker.sha256Hex(ofFileAt: directory.url.appendingPathComponent("missing")))
    }

    // MARK: Archive and signature

    func testOnlyAnArchiveHoldingExactlyTheAppIsAccepted() {
        XCTAssertEqual(Checker.acceptedBundleName(among: ["Rote.app"]), "Rote.app")
        for entries in [[], ["rote.app"], ["Rote.app", "README.md"], ["Rote.app", "__MACOSX"], ["Rote 2.app"], ["Rote.app "], ["Rote.app\u{200B}"], ["x\" & (character id 39) & \".app"]] {
            XCTAssertNil(Checker.acceptedBundleName(among: entries), "\(entries)")
        }
    }

    func testTheRequirementNamesTheTeamAndTheIdentifierAndCompiles() {
        XCTAssertEqual(Checker.codeRequirement,
                       "anchor apple generic and certificate leaf[subject.OU] = \"KHCY27H5KH\" and identifier \"com.beyondthecode.rote\"")
        var requirement: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(Checker.codeRequirement as CFString, [], &requirement), errSecSuccess)
        XCTAssertNotNil(requirement)
    }

    func testAnUnsignedBundleFailsVerification() throws {
        let directory = try TemporaryDirectory()
        addTeardownBlock { directory.remove() }
        let bundle = try makeBundle(in: directory.url, version: "9.9.9")
        XCTAssertThrowsError(try Checker.verifySignature(ofBundleAt: bundle)) { error in
            guard case Checker.UpdateError.signatureInvalid? = error as? Checker.UpdateError else {
                return XCTFail("\(error)")
            }
        }
        XCTAssertThrowsError(try Checker.verifySignature(ofBundleAt: directory.url.appendingPathComponent("missing.app")))
    }

    func testTheExtractedBundlesVersionIsReadFromItsInfoPlist() throws {
        let directory = try TemporaryDirectory()
        addTeardownBlock { directory.remove() }
        XCTAssertEqual(try Checker.shortVersion(ofBundleAt: try makeBundle(in: directory.url, version: "1.0.2")), "1.0.2")
        let noVersion = directory.url.appendingPathComponent("Other.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: noVersion, withIntermediateDirectories: true)
        try Data("<plist version=\"1.0\"><dict/></plist>".utf8).write(to: noVersion.appendingPathComponent("Info.plist"))
        XCTAssertThrowsError(try Checker.shortVersion(ofBundleAt: noVersion.deletingLastPathComponent())) { error in
            XCTAssertEqual(error as? Checker.UpdateError, .noAppInArchive)
        }
    }

    func testAPrivateDirectoryIsFreshAndOwnerOnly() throws {
        let parent = try TemporaryDirectory()
        addTeardownBlock { parent.remove() }
        let first = try Checker.makePrivateDirectory(prefix: "Rote-test", in: parent.url)
        let second = try Checker.makePrivateDirectory(prefix: "Rote-test", in: parent.url)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.lastPathComponent.hasPrefix("Rote-test."))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions] as? Int, 0o700)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: first.path), [])
    }

    func testWritabilityNeedsTheBundleAndItsFolder() throws {
        let directory = try TemporaryDirectory()
        addTeardownBlock { directory.remove() }
        let bundle = try makeBundle(in: directory.url, version: "1.0.0")
        XCTAssertTrue(Checker.isUserWritable(bundle))
        XCTAssertFalse(Checker.isUserWritable(URL(fileURLWithPath: "/System/Applications/Calculator.app")))
        XCTAssertFalse(Checker.isUserWritable(URL(fileURLWithPath: "/System/Applications/Missing.app")))
    }

    // MARK: Privileged step

    func testTheAppleScriptLiteralEscapesWhatAppleScriptWouldRead() {
        XCTAssertEqual(Checker.appleScriptLiteral("plain"), "\"plain\"")
        XCTAssertEqual(Checker.appleScriptLiteral("a\"b"), "\"a\\\"b\"")
        XCTAssertEqual(Checker.appleScriptLiteral("a\\b"), "\"a\\\\b\"")
        XCTAssertEqual(Checker.appleScriptLiteral("a\nb\tc\rd"), "\"a\\nb\\tc\\rd\"")
        XCTAssertEqual(Checker.appleScriptLiteral("x\" & (character id 39) & \"; touch proof; echo \" & (character id 39) & \".app"),
                       "\"x\\\" & (character id 39) & \\\"; touch proof; echo \\\" & (character id 39) & \\\".app\"")
    }

    func testThePrivilegedScriptTakesItsPathsOnlyAsArguments() throws {
        let script = Checker.privilegedInstallScript
        XCTAssertTrue(script.contains("src=$1; dst=$2; req=$3"))
        XCTAssertTrue(script.contains("/usr/bin/codesign --verify --strict --deep -R=\"$req\" \"$stage/new.app\""))
        XCTAssertTrue(script.contains("/usr/bin/mktemp -d \"$parent/.update-staging.XXXXXX\""))
        XCTAssertFalse(script.contains("/Applications"), "no path is written into the script")
        XCTAssertFalse(script.contains("Rote"), "the bundle name is not written into the script either")
        for command in ["cp", "mv", "rm", "mktemp", "dirname", "codesign"] {
            XCTAssertFalse(script.contains(" \(command) "), "\(command) is called by absolute path")
        }
        try XCTAssertEqual(shell(["-n", "-c", script]).status, 0, "the script parses")

        let source = URL(fileURLWithPath: "/private/tmp/Rote-install.abc123/Rote.app")
        let destination = URL(fileURLWithPath: "/Applications/Rote.app")
        let appleScript = Checker.privilegedInstallAppleScript(source: source, destination: destination)
        XCTAssertTrue(appleScript.hasPrefix("do shell script \"/bin/sh -c \" & quoted form of \""))
        XCTAssertTrue(appleScript.hasSuffix(" with administrator privileges"))
        XCTAssertTrue(appleScript.contains("& \" update-installer \" & quoted form of \"/private/tmp/Rote-install.abc123/Rote.app\" & \" \" & quoted form of \"/Applications/Rote.app\" & \" \" & quoted form of \"anchor apple generic and certificate leaf[subject.OU] = \\\"KHCY27H5KH\\\" and identifier \\\"com.beyondthecode.rote\\\"\""))
        XCTAssertEqual(appleScript.components(separatedBy: "quoted form of").count, 5, "the script and its three arguments")
        XCTAssertNotNil(NSAppleScript(source: appleScript), "AppleScript accepts the source")
    }

    /// The script as the current user: a bundle that fails the requirement is never swapped in,
    /// the installed bundle is untouched and no staging folder is left behind.
    func testThePrivilegedScriptRefusesABundleThatFailsTheRequirementAndLeavesTheInstalledOne() throws {
        let directory = try TemporaryDirectory()
        addTeardownBlock { directory.remove() }
        let installed = try makeBundle(in: directory.url.appendingPathComponent("Applications", isDirectory: true), version: "1.0.1")
        let marker = installed.appendingPathComponent("Contents/installed-marker")
        try Data("old".utf8).write(to: marker)
        let candidate = try makeBundle(in: directory.url.appendingPathComponent("extracted", isDirectory: true), version: "1.0.2")

        let result = try shell(["-c", Checker.privilegedInstallScript, "test", candidate.path, installed.path, Checker.codeRequirement])
        XCTAssertEqual(result.status, Checker.privilegedSignatureFailure, result.stderr)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "the installed bundle is untouched")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path), ["Rote.app"], "no staging folder is left")
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.path), "the candidate is left for the caller to remove")
    }

    func testThePrivilegedScriptRefusesALinkOrAMissingDestination() throws {
        let directory = try TemporaryDirectory()
        addTeardownBlock { directory.remove() }
        let installed = try makeBundle(in: directory.url.appendingPathComponent("Applications", isDirectory: true), version: "1.0.1")
        let candidate = try makeBundle(in: directory.url.appendingPathComponent("extracted", isDirectory: true), version: "1.0.2")
        let link = directory.url.appendingPathComponent("Rote.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: candidate)

        XCTAssertEqual(try shell(["-c", Checker.privilegedInstallScript, "test", link.path, installed.path, Checker.codeRequirement]).status, 64, "a link as the source")
        XCTAssertEqual(try shell(["-c", Checker.privilegedInstallScript, "test", candidate.path, directory.url.appendingPathComponent("Missing.app").path, Checker.codeRequirement]).status, 65, "a missing destination")
        XCTAssertEqual(try shell(["-c", Checker.privilegedInstallScript, "test", candidate.path, directory.url.path, Checker.codeRequirement]).status, 65, "a destination that is not an app")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path), ["Rote.app"])
    }

    /// With a bundle that satisfies the requirement (a shipped Rote, named by ROTE_SIGNED_APP or
    /// installed in /Applications), the script swaps it in as the user and removes its staging.
    func testThePrivilegedScriptSwapsInABundleThatSatisfiesTheRequirement() throws {
        let signed = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ROTE_SIGNED_APP"] ?? "/Applications/Rote.app")
        guard (try? Checker.verifySignature(ofBundleAt: signed)) != nil else {
            throw XCTSkip("no bundle satisfying the requirement at \(signed.path)")
        }
        let directory = try TemporaryDirectory()
        addTeardownBlock { directory.remove() }
        let installed = try makeBundle(in: directory.url.appendingPathComponent("Applications", isDirectory: true), version: "0.0.1")
        let extracted = directory.url.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        let candidate = extracted.appendingPathComponent("Rote.app")
        try FileManager.default.copyItem(at: signed, to: candidate)

        let result = try shell(["-c", Checker.privilegedInstallScript, "test", candidate.path, installed.path, Checker.codeRequirement])
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertNoThrow(try Checker.verifySignature(ofBundleAt: installed))
        XCTAssertEqual(try Checker.shortVersion(ofBundleAt: installed), try Checker.shortVersion(ofBundleAt: signed))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path), ["Rote.app"], "the previous bundle and the staging folder are gone")
    }

    // MARK: Helpers

    /// A bare, unsigned `Rote.app` with an Info.plist carrying `version`.
    private func makeBundle(in parent: URL, version: String) throws -> URL {
        let bundle = parent.appendingPathComponent("Rote.app", isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.beyondthecode.rote", "CFBundleShortVersionString": version, "CFBundleExecutable": "Rote"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try Data("#!/bin/sh\n".utf8).write(to: contents.appendingPathComponent("MacOS/Rote"))
        return bundle
    }

    private func shell(_ arguments: [String]) throws -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

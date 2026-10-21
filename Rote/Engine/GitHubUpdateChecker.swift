import AppKit
import CryptoKit
import Foundation
import Security
import os

/// Finds the newest GitHub release and installs it after verifying it.
///
/// Only the release JSON is trusted, and only for the version and the two asset URLs. Nothing
/// read from the network or from the archive is ever built into a shell command or an
/// AppleScript: the asset names follow from the tag, the zip must match the release's `.sha256`
/// asset, the archive must hold exactly one item named `Rote.app`, and that bundle must carry
/// a valid Developer ID signature from this app's team and identifier and a newer version than
/// the running one. The installed bundle is then replaced by a rename swap: as the user when the
/// bundle is theirs (Homebrew, drag to Applications), with no password; otherwise by one fixed
/// privileged script that copies the bundle into a root-owned folder and checks the signature
/// again there before swapping it in. The previous bundle is removed only after the new one is
/// in place and verified, and the quarantine attribute is left alone.
enum GitHubUpdateChecker {

    /// The newest release and how to get it.
    enum UpdateResult: Equatable, Sendable {
        case upToDate
        case available(AvailableUpdate)
    }

    struct AvailableUpdate: Equatable, Sendable {
        enum Source: Equatable, Sendable {
            /// The release carries the pinned zip and its checksum: Rote can fetch, verify and install it.
            case download(ReleaseDownload)
            /// The release lacks them: the user opens its page in the browser instead.
            case page(URL)
        }

        let version: String
        let source: Source
    }

    struct ReleaseDownload: Equatable, Sendable {
        let version: String
        let zipURL: URL
        let checksumURL: URL
    }

    /// A zip in a fresh private directory whose SHA-256 matched the release's `.sha256` asset when it arrived.
    struct DownloadedUpdate: Equatable, Sendable {
        let version: String
        let zipURL: URL
        /// Lowercase hex, 64 characters.
        let expectedSHA256: String
    }

    private static let logger = Logger(subsystem: "com.beyondthecode.rote", category: "updater")

    private static let repoOwner = "beyondthecode-bc"
    private static let repoName = "Rote"

    static let appName = "Rote"
    static let bundleName = "Rote.app"
    static let bundleIdentifier = "com.beyondthecode.rote"
    static let teamIdentifier = "KHCY27H5KH"

    /// The designated requirement every installed bundle must satisfy: Apple's Developer ID
    /// chain, this team, this identifier. The privileged script receives the same text.
    static let codeRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\" and identifier \"\(bundleIdentifier)\""

    // MARK: Check

    static func checkForUpdate(currentVersion: String) async throws -> UpdateResult {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.serverError
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UpdateError.invalidResponse
        }
        return try release(from: json, currentVersion: currentVersion)
    }

    /// The decision from the release JSON: the tag must be `v<major>.<minor>.<patch>`, and the
    /// download is offered only when the release carries exactly `Rote-v<version>.zip` and
    /// `Rote-v<version>.zip.sha256`, both served by github.com over HTTPS. Any other newer
    /// release opens its page in the browser.
    static func release(from json: [String: Any], currentVersion: String) throws -> UpdateResult {
        guard let tagName = json["tag_name"] as? String, let latestVersion = version(fromTag: tagName) else {
            throw UpdateError.invalidResponse
        }
        guard isNewer(latestVersion, than: currentVersion) else {
            return .upToDate
        }

        let assets = (json["assets"] as? [[String: Any]] ?? []).compactMap { asset -> (name: String, url: URL)? in
            guard let name = asset["name"] as? String,
                  let urlString = asset["browser_download_url"] as? String,
                  let url = URL(string: urlString) else { return nil }
            return (name, url)
        }
        if let download = releaseDownload(version: latestVersion, assets: assets) {
            return .available(AvailableUpdate(version: latestVersion, source: .download(download)))
        }
        if let page = (json["html_url"] as? String).flatMap({ URL(string: $0) }), isGitHubHTTPS(page) {
            return .available(AvailableUpdate(version: latestVersion, source: .page(page)))
        }
        throw UpdateError.noDownloadAsset
    }

    /// "v1.2.3" → "1.2.3"; anything else (no "v", a suffix, fewer or more parts) is nil.
    static func version(fromTag tag: String) -> String? {
        guard let match = tag.wholeMatch(of: #/v(\d+)\.(\d+)\.(\d+)/#) else { return nil }
        return "\(match.1).\(match.2).\(match.3)"
    }

    static func zipAssetName(for version: String) -> String {
        "\(appName)-v\(version).zip"
    }

    static func releaseDownload(version: String, assets: [(name: String, url: URL)]) -> ReleaseDownload? {
        let zipName = zipAssetName(for: version)
        guard let zip = assets.first(where: { $0.name == zipName })?.url, isGitHubHTTPS(zip),
              let checksum = assets.first(where: { $0.name == zipName + ".sha256" })?.url, isGitHubHTTPS(checksum) else {
            return nil
        }
        return ReleaseDownload(version: version, zipURL: zip, checksumURL: checksum)
    }

    static func isGitHubHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host()?.lowercased() == "github.com"
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = candidate.split(separator: ".").compactMap { Int($0) }
        let rhs = current.split(separator: ".").compactMap { Int($0) }
        let count = max(lhs.count, rhs.count)
        for i in 0..<count {
            let a = i < lhs.count ? lhs[i] : 0
            let b = i < rhs.count ? rhs[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    // MARK: Download

    /// Fetches the checksum and the zip into a fresh private directory and refuses the zip
    /// unless its SHA-256 is the one the release published.
    static func downloadUpdate(_ download: ReleaseDownload, progress: @escaping @Sendable (Double) -> Void) async throws -> DownloadedUpdate {
        let zipName = zipAssetName(for: download.version)

        let (checksumData, checksumResponse) = try await URLSession.shared.data(from: download.checksumURL)
        guard let http = checksumResponse as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.downloadFailed
        }
        guard checksumData.count <= 4096, let checksumText = String(data: checksumData, encoding: .utf8),
              let expected = expectedDigest(inChecksumFile: checksumText, assetName: zipName) else {
            throw UpdateError.checksumMismatch
        }

        let (tempURL, response) = try await URLSession.shared.download(from: download.zipURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw UpdateError.downloadFailed
        }

        let directory = try makePrivateDirectory(prefix: "\(appName)-update", in: FileManager.default.temporaryDirectory)
        let zipURL = directory.appendingPathComponent(zipName)
        do {
            try FileManager.default.moveItem(at: tempURL, to: zipURL)
            guard try sha256Hex(ofFileAt: zipURL) == expected else { throw UpdateError.checksumMismatch }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: directory)
            throw error
        }

        progress(1.0)
        logger.info("Update \(download.version, privacy: .public) downloaded and checksum verified")
        return DownloadedUpdate(version: download.version, zipURL: zipURL, expectedSHA256: expected)
    }

    /// The digest in a `shasum -a 256` line ("<64 hex>  <file name>"), lowercase; nil unless the
    /// digest is well formed and the named file, when there is one, is the expected asset.
    static func expectedDigest(inChecksumFile text: String, assetName: String) -> String? {
        let fields = text.split(whereSeparator: \.isWhitespace)
        guard let first = fields.first, fields.count <= 2 else { return nil }
        let digest = first.lowercased()
        guard digest.count == 64, digest.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
        if fields.count == 2 {
            var name = Substring(fields[1])
            if name.hasPrefix("*") { name = name.dropFirst() }   // shasum's binary-mode marker
            guard name == assetName else { return nil }
        }
        return digest
    }

    static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Install

    /// Verifies and installs a downloaded update, then relaunches. Throws, with the installed
    /// app untouched, when the zip no longer matches its checksum, the archive is not exactly
    /// `Rote.app`, the bundle's signature is not this team's, or its version is not newer.
    static func installUpdate(_ update: DownloadedUpdate) async throws {
        let fileManager = FileManager.default
        guard try sha256Hex(ofFileAt: update.zipURL) == update.expectedSHA256 else {
            throw UpdateError.checksumMismatch
        }

        let destination = Bundle.main.bundleURL
        guard destination.pathExtension == "app" else {
            throw UpdateError.installFailed("Not running from an app bundle")
        }

        // Fresh, private, and on the destination's volume where possible, so the swap is a rename.
        let workDirectory = try makeWorkDirectory(near: destination)
        defer { try? fileManager.removeItem(at: workDirectory) }

        try extract(update.zipURL, into: workDirectory)
        let newBundle = try extractedBundle(in: workDirectory)
        try verifySignature(ofBundleAt: newBundle)

        let newVersion = try shortVersion(ofBundleAt: newBundle)
        let runningVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        guard isNewer(newVersion, than: runningVersion) else {
            throw UpdateError.notNewer
        }

        if isUserWritable(destination) {
            try replaceAsUser(destination, with: newBundle, keepingPreviousIn: workDirectory)
        } else {
            try replaceWithAdministratorPrivileges(destination, with: newBundle)
        }
        try verifySignature(ofBundleAt: destination)
        try? fileManager.removeItem(at: update.zipURL.deletingLastPathComponent())
        logger.info("Update \(newVersion, privacy: .public) installed at \(destination.path, privacy: .public)")

        await relaunch(destination)
    }

    /// A `mkdtemp` directory (mode 0700) in `parent`.
    static func makePrivateDirectory(prefix: String, in parent: URL) throws -> URL {
        var template = Array(parent.appendingPathComponent("\(prefix).XXXXXX").path.utf8CString)
        guard let created = mkdtemp(&template) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return URL(fileURLWithPath: String(cString: created), isDirectory: true)
    }

    private static func makeWorkDirectory(near destination: URL) throws -> URL {
        let fileManager = FileManager.default
        if let sameVolume = try? fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true) {
            do {
                return try makePrivateDirectory(prefix: "\(appName)-install", in: sameVolume)
            } catch {
                try? fileManager.removeItem(at: sameVolume)
            }
        }
        return try makePrivateDirectory(prefix: "\(appName)-install", in: fileManager.temporaryDirectory)
    }

    private static func extract(_ zipURL: URL, into directory: URL) throws {
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-xk", zipURL.path, directory.path]
        do {
            try unzip.run()
        } catch {
            throw UpdateError.extractFailed
        }
        unzip.waitUntilExit()
        guard unzip.terminationReason == .exit, unzip.terminationStatus == 0 else {
            throw UpdateError.extractFailed
        }
    }

    /// The archive's one item must be named exactly `Rote.app`.
    static func acceptedBundleName(among entries: [String]) -> String? {
        entries == [bundleName] ? bundleName : nil
    }

    private static func extractedBundle(in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(atPath: directory.path)
        guard let name = acceptedBundleName(among: entries) else {
            throw UpdateError.noAppInArchive
        }
        let bundle = directory.appendingPathComponent(name, isDirectory: true)
        // attributesOfItem does not follow symbolic links: a link named Rote.app is rejected.
        let type = try fileManager.attributesOfItem(atPath: bundle.path)[.type] as? FileAttributeType
        guard type == .typeDirectory else {
            throw UpdateError.noAppInArchive
        }
        return bundle
    }

    /// Strict static validation of every architecture and all nested code against `codeRequirement`.
    static func verifySignature(ofBundleAt url: URL) throws {
        var staticCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard status == errSecSuccess, let code = staticCode else {
            throw UpdateError.signatureInvalid(securityMessage(status))
        }
        var requirement: SecRequirement?
        status = SecRequirementCreateWithString(codeRequirement as CFString, [], &requirement)
        guard status == errSecSuccess, let requirement else {
            throw UpdateError.signatureInvalid(securityMessage(status))
        }
        let flags = SecCSFlags(rawValue: UInt32(kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode))
        var error: Unmanaged<CFError>?
        status = SecStaticCodeCheckValidityWithErrors(code, flags, requirement, &error)
        if let error = error?.takeRetainedValue() {
            throw UpdateError.signatureInvalid(error.localizedDescription)
        }
        guard status == errSecSuccess else {
            throw UpdateError.signatureInvalid(securityMessage(status))
        }
    }

    private static func securityMessage(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
    }

    static func shortVersion(ofBundleAt bundle: URL) throws -> String {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = info["CFBundleShortVersionString"] as? String else {
            throw UpdateError.noAppInArchive
        }
        return version
    }

    /// True when the user can rename the bundle out of its folder and the new one in.
    static func isUserWritable(_ bundle: URL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.isWritableFile(atPath: bundle.path)
            && fileManager.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
    }

    /// Rename swap as the user: the running bundle moves aside, the verified one moves in and is
    /// checked again in place; any failure moves the previous bundle back.
    private static func replaceAsUser(_ destination: URL, with newBundle: URL, keepingPreviousIn workDirectory: URL) throws {
        let fileManager = FileManager.default
        let previous = workDirectory.appendingPathComponent("previous.app", isDirectory: true)
        do {
            try fileManager.moveItem(at: destination, to: previous)
        } catch {
            throw UpdateError.installFailed(error.localizedDescription)
        }
        do {
            try fileManager.moveItem(at: newBundle, to: destination)
            try verifySignature(ofBundleAt: destination)
        } catch {
            try? fileManager.removeItem(at: destination)
            try? fileManager.moveItem(at: previous, to: destination)
            if case UpdateError.signatureInvalid = error { throw error }
            throw UpdateError.installFailed(error.localizedDescription)
        }
        // The previous bundle is deleted with the work directory.
    }

    /// The whole privileged step, run by `/bin/sh -c` with the source bundle, the destination
    /// and the requirement as `$1`, `$2` and `$3`. It copies the bundle into a root-owned
    /// staging folder beside the destination and verifies that copy, so nothing the user can
    /// write is read as root after the check, then swaps by rename and moves the previous
    /// bundle back if the swap fails.
    static let privilegedInstallScript = """
        set -u
        src=$1; dst=$2; req=$3
        [ -d "$src" ] && [ ! -L "$src" ] || exit 64
        case "$dst" in *.app) ;; *) exit 65 ;; esac
        [ -d "$dst" ] && [ ! -L "$dst" ] || exit 65
        parent=$(/usr/bin/dirname "$dst") || exit 66
        stage=$(/usr/bin/mktemp -d "$parent/.update-staging.XXXXXX") || exit 66
        if ! /bin/cp -RP "$src" "$stage/new.app" || [ ! -d "$stage/new.app" ] || [ -L "$stage/new.app" ]; then
          /bin/rm -rf "$stage"; exit 67
        fi
        if ! /usr/bin/codesign --verify --strict --deep -R="$req" "$stage/new.app"; then
          /bin/rm -rf "$stage"; exit 68
        fi
        if ! /bin/mv "$dst" "$stage/previous.app"; then
          /bin/rm -rf "$stage"; exit 69
        fi
        if ! /bin/mv "$stage/new.app" "$dst"; then
          /bin/rm -rf "$dst"
          /bin/mv "$stage/previous.app" "$dst" || exit 71
          /bin/rm -rf "$stage"; exit 70
        fi
        /bin/rm -rf "$stage"
        exit 0
        """

    /// Exit statuses of `privilegedInstallScript` that have their own message.
    static let privilegedSignatureFailure: Int32 = 68

    /// `text` as an AppleScript string literal. The values it carries are this app's constants
    /// (the script, the paths it chose, the requirement); nothing from the archive reaches it.
    static func appleScriptLiteral(_ text: String) -> String {
        var escaped = ""
        for character in text {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default: escaped.append(character)
            }
        }
        return "\"" + escaped + "\""
    }

    /// The AppleScript that runs the fixed script with its three arguments, each passed through
    /// `quoted form of`.
    static func privilegedInstallAppleScript(source: URL, destination: URL) -> String {
        "do shell script \"/bin/sh -c \" & quoted form of \(appleScriptLiteral(privilegedInstallScript))"
            + " & \" update-installer \" & quoted form of \(appleScriptLiteral(source.path))"
            + " & \" \" & quoted form of \(appleScriptLiteral(destination.path))"
            + " & \" \" & quoted form of \(appleScriptLiteral(codeRequirement))"
            + " with administrator privileges"
    }

    private static func replaceWithAdministratorPrivileges(_ destination: URL, with newBundle: URL) throws {
        for path in [newBundle.path, destination.path] {
            guard !path.contains(where: { $0.isNewline || ($0.asciiValue.map { $0 < 0x20 } ?? false) }) else {
                throw UpdateError.installFailed("Unexpected characters in a path")
            }
        }
        guard let appleScript = NSAppleScript(source: privilegedInstallAppleScript(source: newBundle, destination: destination)) else {
            throw UpdateError.installFailed("Could not create installer script")
        }
        var errorInfo: NSDictionary?
        appleScript.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return }

        let number = errorInfo[NSAppleScript.errorNumber] as? Int
        let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
        if number == -128 || message.lowercased().contains("cancel") {
            throw UpdateError.installFailed("Authorization cancelled")
        }
        if number == Int(privilegedSignatureFailure) {
            throw UpdateError.signatureInvalid(message)
        }
        throw UpdateError.installFailed(message)
    }

    @MainActor
    private static func relaunch(_ bundle: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { _, error in
            if let error {
                logger.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
            }
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            NSApplication.shared.terminate(nil)
        }
    }

    enum UpdateError: LocalizedError, Equatable, Sendable {
        case serverError
        case invalidResponse
        case noDownloadAsset
        case downloadFailed
        case checksumMismatch
        case extractFailed
        case noAppInArchive
        case signatureInvalid(String)
        case notNewer
        case installFailed(String)

        var errorDescription: String? {
            switch self {
            case .serverError: return "Could not reach GitHub. Check your internet connection."
            case .invalidResponse: return "Unexpected response from GitHub."
            case .noDownloadAsset: return "No download found in the latest release."
            case .downloadFailed: return "Download failed."
            case .checksumMismatch: return "The download could not be verified against the checksum published with the release."
            case .extractFailed: return "Could not extract the update archive."
            case .noAppInArchive: return "No app found in the downloaded archive."
            case .signatureInvalid(let reason): return "The downloaded app is not signed by the developer of \(appName): \(reason)"
            case .notNewer: return "The downloaded app is not newer than the installed one."
            case .installFailed(let msg): return "Install failed: \(msg)"
            }
        }
    }
}

import AppKit
import SwiftUI

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate
    case available(GitHubUpdateChecker.AvailableUpdate)
    case downloading
    case downloaded(GitHubUpdateChecker.DownloadedUpdate)
    case installing
    case error(UpdateFailure)
}

/// A failed update step as the key of Rote's message, not its text, so the message follows a
/// language chosen while it is on screen, like the heading above it.
struct UpdateFailure: Equatable {
    let key: String
    /// The system's own reason for a failed install, inserted after Rote's sentence.
    var detail: String?
}

/// The About tab's text for a failed update step, in Rote's language. The shared template
/// checker keeps its English `errorDescription`; each of its cases maps to a key here.
@MainActor
enum UpdateErrorMessage {
    enum Step {
        case check, download, install
    }

    static func failure(for error: any Error, during step: Step) -> UpdateFailure {
        switch error {
        case let error as GitHubUpdateChecker.UpdateError:
            return failure(for: error)
        case is URLError:
            // Offline, timed out or blocked: URLSession's own text would be in the system's language.
            return UpdateFailure(key: "update.error.server")
        default:
            // A page that is not JSON, a file move or a process launch: Foundation's description
            // would be in the system's language, so the step's own message stands in for it.
            switch step {
            case .check: return UpdateFailure(key: "update.error.invalidResponse")
            case .download: return UpdateFailure(key: "update.error.download")
            case .install: return UpdateFailure(key: "update.error.install")
            }
        }
    }

    private static func failure(for error: GitHubUpdateChecker.UpdateError) -> UpdateFailure {
        switch error {
        case .serverError: return UpdateFailure(key: "update.error.server")
        case .invalidResponse: return UpdateFailure(key: "update.error.invalidResponse")
        case .noDownloadAsset: return UpdateFailure(key: "update.error.noDownload")
        case .downloadFailed: return UpdateFailure(key: "update.error.download")
        case .checksumMismatch: return UpdateFailure(key: "update.error.checksum")
        case .extractFailed: return UpdateFailure(key: "update.error.extract")
        case .noAppInArchive: return UpdateFailure(key: "update.error.noApp")
        case .signatureInvalid: return UpdateFailure(key: "update.error.signature")
        case .notNewer: return UpdateFailure(key: "update.error.notNewer")
        case .installFailed(let reason):
            // The checker's own reasons are English literals; anything else is the system's
            // message from the administrator prompt or the copy, shown after Rote's sentence.
            switch reason {
            case "Authorization cancelled": return UpdateFailure(key: "update.error.installCancelled")
            case "Could not create installer script", "Unknown error": return UpdateFailure(key: "update.error.install")
            default: return UpdateFailure(key: "update.error.installDetail", detail: reason)
            }
        }
    }

    static func text(for failure: UpdateFailure, localization: LocalizationManager = .shared) -> String {
        guard let detail = failure.detail else { return localization.string(for: failure.key) }
        return localization.string(for: failure.key, [detail])
    }
}

struct AboutView: View {
    @Environment(AppContainer.self) private var container
    @State private var updateState: UpdateCheckState = .idle

    private let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let repoURL = "https://github.com/beyondthecode-bc/Rote"

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                Divider().padding(.horizontal, 16)
                updatesSection
                Divider().padding(.horizontal, 16)
                languageRow
                Divider().padding(.horizontal, 16)
                supportSection
                Divider().padding(.horizontal, 16)
                compactLinks
            }
            .padding(22)
        }
        .frame(width: DesignTokens.settingsWidth)
        .onAppear(perform: showUpdateFoundAtLaunch)
        .onChange(of: container.updateAvailable?.version) { showUpdateFoundAtLaunch() }
    }

    /// The portfolio's About header: brand logo, name, marketing version only (never the build
    /// number), tagline.
    private var header: some View {
        VStack(spacing: 6) {
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(l("app.name"))
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("v\(shortVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(l("about.tagline"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch updateState {
            case .idle:
                HStack {
                    Spacer()
                    Button { checkForUpdates() } label: {
                        Label(l("update.check"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .controlSize(.small)
                    Spacer()
                }
            case .checking:
                progressRow(l("update.checking"))
            case .upToDate:
                HStack(spacing: 6) {
                    Circle().fill(DesignTokens.learned).frame(width: 5, height: 5)
                    Text(l("update.upToDate")).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button(l("update.recheck")) { checkForUpdates() }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            case .available(let update):
                HStack {
                    Text(l("update.version", update.version)).font(.system(size: 12, weight: .medium))
                    Spacer()
                    switch update.source {
                    case .download(let download):
                        Button(l("update.download")) { self.download(download) }
                            .buttonStyle(.borderedProminent).controlSize(.small).tint(DesignTokens.accent)
                    case .page(let pageURL):
                        // The release lacks the pinned zip and checksum, so Rote cannot verify it: the browser takes over.
                        Button(l("update.viewRelease")) { NSWorkspace.shared.open(pageURL) }
                            .buttonStyle(.borderedProminent).controlSize(.small).tint(DesignTokens.accent)
                    }
                }
            case .downloading:
                progressRow(l("update.downloading"))
            case .downloaded(let update):
                HStack {
                    Text(l("update.ready")).font(.system(size: 12))
                    Spacer()
                    Button(l("update.install")) { install(update) }
                        .buttonStyle(.borderedProminent).controlSize(.small).tint(DesignTokens.accent)
                }
            case .installing:
                progressRow(l("update.installing"))
            case .error(let failure):
                VStack(alignment: .leading, spacing: 4) {
                    Text(l("update.error")).font(.system(size: 12)).foregroundStyle(.red)
                    Text(UpdateErrorMessage.text(for: failure)).font(.system(size: 11)).foregroundStyle(.secondary)
                    Button(l("update.retry")) { checkForUpdates() }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            }
        }
    }

    /// A step in progress shows no button, so it cannot be started twice.
    private func progressRow(_ label: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    /// The interface language, as on the General tab: the same menu, applied at once.
    private var languageRow: some View {
        HStack(spacing: 10) {
            rowIcon(symbol: "character.bubble.fill", tint: .purple)
            VStack(alignment: .leading, spacing: 1) {
                Text(l("settings.language")).font(.system(size: 12, weight: .medium))
                // Wraps rather than truncates: the menu is as wide as its longest language name.
                Text(l("settings.language.note"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            LanguagePicker()
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.06)))
    }

    private var supportSection: some View {
        VStack(spacing: 6) {
            linkRow(symbol: "heart.fill", tint: .pink, title: l("about.sponsor"), subtitle: l("about.sponsor.subtitle"), url: "https://github.com/sponsors/beyondthecode-bc")
            linkRow(symbol: "cup.and.saucer.fill", tint: .yellow, title: l("about.coffee"), subtitle: l("about.coffee.subtitle"), url: "https://www.buymeacoffee.com/BEYONDTHECODE")
        }
    }

    /// GitHub, Translations, Report Issue: the portfolio's compact links row.
    private var compactLinks: some View {
        HStack(spacing: 6) {
            compactLink(symbol: "chevron.left.forwardslash.chevron.right", title: "GitHub", url: repoURL)
            compactLink(symbol: "globe", title: l("about.translations"), url: "\(repoURL)/tree/main/languages")
            compactLink(symbol: "exclamationmark.bubble.fill", title: l("about.reportIssue"), url: "\(repoURL)/issues")
        }
    }

    private func linkRow(symbol: String, tint: Color, title: String, subtitle: String, url: String) -> some View {
        Button {
            if let link = URL(string: url) { NSWorkspace.shared.open(link) }
        } label: {
            HStack(spacing: 10) {
                rowIcon(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A white symbol on a tinted rounded square, as the portfolio's About rows show them.
    private func rowIcon(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(tint.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func compactLink(symbol: String, title: String, url: String) -> some View {
        Button {
            if let link = URL(string: url) { NSWorkspace.shared.open(link) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(title).font(.system(size: 9)).lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.secondary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Update actions (template GitHubUpdateChecker: check, download, install)

    /// The popover's "Rote X is available" opens this tab, so the launch check's find shows here
    /// with its Download button instead of asking the user to check again.
    private func showUpdateFoundAtLaunch() {
        guard updateState == .idle, let update = container.updateAvailable else { return }
        updateState = .available(update)
    }

    private func checkForUpdates() {
        updateState = .checking
        Task {
            do {
                switch try await GitHubUpdateChecker.checkForUpdate(currentVersion: shortVersion) {
                case .upToDate:
                    updateState = .upToDate
                case .available(let update):
                    updateState = .available(update)
                }
            } catch {
                updateState = .error(UpdateErrorMessage.failure(for: error, during: .check))
            }
        }
    }

    /// Like `checkForUpdates`, each step changes the state before its first await, so its button
    /// is gone before a second click can start it again: a second install would race the first
    /// one's rename swap and could ask for the administrator password again. The download
    /// reports progress only when it ends, so it shows a spinner rather than a bar.
    private func download(_ download: GitHubUpdateChecker.ReleaseDownload) {
        updateState = .downloading
        Task {
            do {
                let update = try await GitHubUpdateChecker.downloadUpdate(download) { @Sendable _ in }
                updateState = .downloaded(update)
            } catch {
                updateState = .error(UpdateErrorMessage.failure(for: error, during: .download))
            }
        }
    }

    /// On success the installer relaunches Rote, so `.installing` stays until the app quits.
    private func install(_ update: GitHubUpdateChecker.DownloadedUpdate) {
        updateState = .installing
        Task {
            do {
                try await GitHubUpdateChecker.installUpdate(update)
            } catch {
                updateState = .error(UpdateErrorMessage.failure(for: error, during: .install))
            }
        }
    }
}

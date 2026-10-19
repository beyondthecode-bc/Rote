import AppKit
import SwiftUI

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String, downloadURL: URL)
    case downloading
    case downloaded(path: String)
    case installing
    case error(String)
}

struct AboutView: View {
    @Environment(AppContainer.self) private var container
    @State private var updateState: UpdateCheckState = .idle

    private let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let repoURL = "https://github.com/beyondthecode-bc/Rote"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Divider()
                versionSection
                Divider()
                updatesSection
                Divider()
                repoSection
                Divider()
                supportSection
            }
            .padding(22)
        }
        .frame(width: DesignTokens.settingsWidth)
        .onAppear(perform: showUpdateFoundAtLaunch)
        .onChange(of: container.updateAvailable?.version) { showUpdateFoundAtLaunch() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(l("app.name")).font(.system(size: 20, weight: .bold, design: .rounded))
                Text(l("about.tagline")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: l("about.version"))
            HStack {
                Text(l("about.version.label")).font(.system(size: 12))
                Spacer()
                Text(shortVersion)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: l("update.title"))
            switch updateState {
            case .idle:
                HStack {
                    Text(l("update.check")).font(.system(size: 12))
                    Spacer()
                    Button(l("update.check")) { checkForUpdates() }
                        .buttonStyle(.bordered).controlSize(.small)
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
            case .available(let version, let url):
                HStack {
                    Text(l("update.version", version)).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button(l("update.download")) { download(from: url) }
                        .buttonStyle(.borderedProminent).controlSize(.small).tint(DesignTokens.accent)
                }
            case .downloading:
                progressRow(l("update.downloading"))
            case .downloaded(let path):
                HStack {
                    Text(l("update.ready")).font(.system(size: 12))
                    Spacer()
                    Button(l("update.install")) { install(from: path) }
                        .buttonStyle(.borderedProminent).controlSize(.small).tint(DesignTokens.accent)
                }
            case .installing:
                progressRow(l("update.installing"))
            case .error(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Text(l("update.error")).font(.system(size: 12)).foregroundStyle(.red)
                    Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
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

    private var repoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: l("about.github"))
            linkRow(glyph: AnyView(BrandIcons.GitHubMark(size: 18)), title: l("about.githubProject"), subtitle: l("about.githubProject.subtitle"), url: repoURL)
        }
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: l("about.support"))
            VStack(spacing: 8) {
                linkRow(glyph: AnyView(BrandIcons.GitHubMark(size: 18)), title: l("about.sponsor"), subtitle: l("about.sponsor.subtitle"), url: "https://github.com/sponsors/beyondthecode-bc")
                linkRow(glyph: AnyView(BrandIcons.CoffeeMark(size: 18)), title: l("about.coffee"), subtitle: l("about.coffee.subtitle"), url: "https://www.buymeacoffee.com/BEYONDTHECODE")
            }
        }
    }

    private func linkRow(glyph: AnyView, title: String, subtitle: String, url: String) -> some View {
        Button {
            if let link = URL(string: url) { NSWorkspace.shared.open(link) }
        } label: {
            HStack(spacing: 12) {
                glyph.frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DesignTokens.surfaceMuted))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DesignTokens.hairline, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Update actions (template GitHubUpdateChecker: check, download, install)

    /// The popover's "Rote X is available" opens this tab, so the launch check's find shows here
    /// with its Download button instead of asking the user to check again.
    private func showUpdateFoundAtLaunch() {
        guard updateState == .idle, let update = container.updateAvailable else { return }
        updateState = .available(version: update.version, downloadURL: update.url)
    }

    private func checkForUpdates() {
        updateState = .checking
        Task {
            do {
                switch try await GitHubUpdateChecker.checkForUpdate(currentVersion: shortVersion) {
                case .upToDate:
                    updateState = .upToDate
                case .available(let version, let url):
                    updateState = .available(version: version, downloadURL: url)
                }
            } catch {
                updateState = .error(error.localizedDescription)
            }
        }
    }

    /// Like `checkForUpdates`, each step changes the state before its first await, so its button
    /// is gone before a second click can start it again: a second install would delete the folder
    /// the first one copies from and ask for the administrator password again. The download
    /// reports progress only when it ends, so it shows a spinner rather than a bar.
    private func download(from url: URL) {
        updateState = .downloading
        Task {
            do {
                let path = try await GitHubUpdateChecker.downloadUpdate(from: url) { @Sendable _ in }
                updateState = .downloaded(path: path)
            } catch {
                updateState = .error(error.localizedDescription)
            }
        }
    }

    /// On success the installer relaunches Rote, so `.installing` stays until the app quits.
    private func install(from path: String) {
        updateState = .installing
        Task {
            do {
                try await GitHubUpdateChecker.installUpdate(fromZip: path)
            } catch {
                updateState = .error(error.localizedDescription)
            }
        }
    }
}

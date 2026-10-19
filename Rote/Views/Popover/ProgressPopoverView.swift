import AppKit
import RoteCore
import SwiftUI

/// The menu bar popover (spec §7.3).
struct ProgressPopoverView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openSettings) private var openSettings
    @State private var learnedExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if container.engine.permissionGranted {
                content
            } else {
                PermissionStepView(granted: false)
                    .padding(14)
            }
            Divider()
            footer
        }
        .frame(width: DesignTokens.popoverWidth)
    }

    // MARK: Header

    private var header: some View {
        let engine = container.engine
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: MenuBarIcon.image(for: .normal))
                    .accessibilityHidden(true)
                Text(l("popover.thisWeek"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                pauseMenu
            }
            if engine.isPaused, let until = engine.pauseUntil {
                Text(engine.isPausedUntilResumed
                    ? l("popover.pausedIndefinitely")
                    : l("popover.pausedUntil", until.formatted(date: .omitted, time: .shortened)))
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var pauseMenu: some View {
        let engine = container.engine
        return Menu {
            if engine.isPaused {
                Button(l("popover.resume")) { engine.resume() }
            } else {
                Button(l("popover.pauseHour")) { engine.pause(for: 3_600) }
                Button(l("popover.pauseToday")) { engine.pauseUntilTomorrow() }
                Button(l("popover.pauseUntilResumed")) { engine.pauseUntilResumed() }
            }
        } label: {
            Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 10, weight: .bold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(engine.isPaused ? l("popover.resume") : l("popover.pause"))
    }

    // MARK: Content

    private var content: some View {
        let engine = container.engine
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let update = container.updateAvailable {
                    noticeRow(l("popover.updateAvailable", update.version), symbol: "arrow.down.circle", button: l("menu.about")) {
                        openSettingsTab(.about)
                    }
                }
                if let name = engine.recoveredCorruptFile {
                    noticeRow(l("popover.recovered", name), symbol: "exclamationmark.triangle", button: l("general.ok")) {
                        engine.acknowledgeRecoveryNotice()
                    }
                }
                tiles(engine.weeklyStats)
                coachingSection(engine.coachingNow)
                learnedSection(engine.learnedRecently, total: engine.learnedTotal)
            }
            .padding(14)
        }
        .frame(maxHeight: DesignTokens.popoverMaxHeight - 90)
    }

    private func noticeRow(_ text: String, symbol: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(DesignTokens.accent)
            Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(button, action: action).controlSize(.small)
        }
        .padding(10)
        .background(DesignTokens.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func tiles(_ stats: WeeklyStats) -> some View {
        HStack(spacing: 8) {
            StatTileView(value: stats.learned, delta: stats.learnedDelta, label: l("stats.learned"))
            StatTileView(value: stats.menuClicksWithShortcut, delta: stats.menuClicksDelta, label: l("stats.menuClicks"), lowerIsBetter: true)
            StatTileView(value: stats.shortcutsUsed, delta: stats.shortcutsUsedDelta, label: l("stats.shortcutsUsed"))
        }
    }

    private func coachingSection(_ records: [ItemRecord]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: l("popover.coachingNow"))
            if records.isEmpty {
                Text(l("popover.empty"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                ForEach(Stats.grouped(records), id: \.bundleID) { group in
                    AppHeaderRow(bundleID: group.bundleID)
                    ForEach(group.records) { record in
                        CoachingRow(record: record) { container.engine.snooze(record.identity) }
                    }
                }
            }
        }
    }

    private func learnedSection(_ records: [ItemRecord], total: Int) -> some View {
        DisclosureGroup(isExpanded: $learnedExpanded) {
            if records.isEmpty {
                Text("—").foregroundStyle(.secondary).font(.system(size: 11))
            } else {
                ForEach(records) { LearnedRow(record: $0) }
            }
        } label: {
            SectionLabel(text: "\(l("popover.learned")) · \(total)")
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button(l("menu.settings")) { openSettingsTab(.general) }
            Button(l("menu.about")) { openSettingsTab(.about) }
            #if DEBUG
            Menu("Debug") {
                Button("Simulate nudge") { container.simulateNudge() }
                Button("Export menu snapshot") { container.exportSnapshot() }
            }
            .fixedSize()
            #endif
            Spacer()
            Button(l("app.quit")) { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func openSettingsTab(_ tab: SettingsTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: SettingsTab.storageKey)
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}

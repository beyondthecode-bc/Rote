import AppKit
import RoteCore
import SwiftUI
import UniformTypeIdentifiers

struct DataSettingsTab: View {
    @Environment(AppContainer.self) private var container
    @State private var confirmReset = false
    @State private var exportError: String?

    var body: some View {
        let engine = container.engine
        Form {
            Text(l("settings.privacy"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Section(l("settings.muted")) {
                if engine.mutedItems.isEmpty {
                    Text("—").foregroundStyle(.secondary)
                } else {
                    ForEach(engine.mutedItems) { record in
                        // Identity includes the app, so the same title can be muted in two apps.
                        let app = AppInfo.resolve(record.item.bundleID)
                        HStack {
                            Image(nsImage: app.icon).resizable().frame(width: 16, height: 16)
                            Text(record.item.title).lineLimit(1)
                            Text(app.name).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            KeycapGroupView(shortcut: record.item.shortcut, size: .popover)
                            Button(l("settings.unmute")) { engine.unmute(record.identity) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
            Section {
                Button(l("settings.export")) { export() }
                Button(l("settings.reset"), role: .destructive) { confirmReset = true }
                if let exportError {
                    Text(exportError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(l("settings.reset"), isPresented: $confirmReset) {
            Button(l("settings.reset"), role: .destructive) { engine.resetStatistics() }
            Button(l("general.cancel"), role: .cancel) {}
        } message: {
            Text(l("settings.resetConfirm"))
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "rote-state.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try container.engine.exportJSON().write(to: url)
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }
}

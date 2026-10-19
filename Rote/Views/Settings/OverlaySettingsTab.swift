import SwiftUI

struct OverlaySettingsTab: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var settings = container.settings
        let holdDelay = Binding<Double>(
            get: { Double(settings.holdDelayMs) },
            set: { settings.holdDelayMs = Int($0) }
        )
        Form {
            Picker(l("settings.trigger"), selection: $settings.overlayTrigger) {
                Text(l("settings.trigger.command")).tag(AppSettings.OverlayTrigger.holdCommand)
                Text(l("settings.trigger.option")).tag(AppSettings.OverlayTrigger.holdOption)
                Text(l("settings.trigger.sticky")).tag(AppSettings.OverlayTrigger.stickyHotkey)
            }
            Slider(value: holdDelay, in: Double(AppSettings.holdDelayMsRange.lowerBound)...Double(AppSettings.holdDelayMsRange.upperBound), step: 50) {
                Text(l("settings.holdDelay", "\(settings.holdDelayMs)"))
            }
            .disabled(settings.overlayTrigger == .stickyHotkey)
            Toggle(l("settings.showNoShortcut"), isOn: $settings.showItemsWithoutShortcuts)
            Toggle(l("settings.showAppleMenu"), isOn: $settings.showAppleMenu)
        }
        .formStyle(.grouped)
    }
}

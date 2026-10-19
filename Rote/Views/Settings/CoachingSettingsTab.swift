import SwiftUI

struct CoachingSettingsTab: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var settings = container.settings
        Form {
            Stepper(l("settings.nudgeAfter", "\(settings.nudgeAfter)"), value: $settings.nudgeAfter, in: AppSettings.nudgeAfterRange)
            Stepper(l("settings.itemSpacing", "\(settings.itemSpacingHours)"), value: $settings.itemSpacingHours, in: AppSettings.itemSpacingHoursRange)
            Stepper(l("settings.dailyCap", "\(settings.dailyCap)"), value: $settings.dailyCap, in: AppSettings.dailyCapRange)
            Slider(value: $settings.hudDuration, in: AppSettings.hudDurationRange, step: 0.5) {
                Text(l("settings.hudDuration", String(format: "%.1f", settings.hudDuration)))
            }
            Toggle(l("settings.sound"), isOn: $settings.soundEnabled)
        }
        .formStyle(.grouped)
        .onChange(of: settings.policy) { _, _ in container.engine.refreshPolicy() }
    }
}

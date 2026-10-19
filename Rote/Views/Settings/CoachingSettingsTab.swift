import SwiftUI

struct CoachingSettingsTab: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var settings = container.settings
        Form {
            Stepper(l("settings.nudgeAfter", count: settings.nudgeAfter, number(settings.nudgeAfter)), value: $settings.nudgeAfter, in: AppSettings.nudgeAfterRange)
            Stepper(l("settings.itemSpacing", count: settings.itemSpacingHours, number(settings.itemSpacingHours)), value: $settings.itemSpacingHours, in: AppSettings.itemSpacingHoursRange)
            Stepper(l("settings.dailyCap", count: settings.dailyCap, number(settings.dailyCap)), value: $settings.dailyCap, in: AppSettings.dailyCapRange)
            Slider(value: $settings.hudDuration, in: AppSettings.hudDurationRange, step: 0.5) {
                // A decimal always takes the plural wording, so this phrase has no .one form.
                Text(l("settings.hudDuration", decimal(settings.hudDuration)))
            }
            Toggle(l("settings.sound"), isOn: $settings.soundEnabled)
        }
        .formStyle(.grouped)
        .onChange(of: settings.policy) { _, _ in container.engine.refreshPolicy() }
    }
}

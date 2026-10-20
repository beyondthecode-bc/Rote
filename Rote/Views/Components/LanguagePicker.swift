import SwiftUI

/// The interface language menu: "System default", then each supported language in its own name.
/// The General and About tabs both show it. A choice applies at once, with no relaunch.
struct LanguagePicker: View {
    var body: some View {
        @Bindable var localization = LocalizationManager.shared
        Picker(l("settings.language"), selection: $localization.languageCode) {
            Text(l("settings.language.system")).tag("system")
            Divider()
            ForEach(LocalizationManager.supportedCodes, id: \.self) { code in
                Text(LocalizationManager.nativeNames[code] ?? code).tag(code)
            }
        }
        .pickerStyle(.menu)
    }
}

import SwiftUI

@main
struct RoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container: AppContainer = MainActor.assumeIsolated { AppContainer.shared }

    var body: some Scene {
        MenuBarExtra {
            StatusPopoverView()
                .environment(container)
        } label: {
            Image(nsImage: MenuBarIcon.image(for: container.iconState))
        }
        .menuBarExtraStyle(.window)
    }
}

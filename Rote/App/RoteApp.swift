import SwiftUI

/// Picks the app to run. A process hosting unit tests runs `TestHostApp`, which has no menu bar
/// extra, so a test run puts no item in the menu bar and writes no status item state to the app's
/// defaults (a hidden extra would still save its visibility there and could hide the real one).
@main
enum RoteMain {
    @MainActor static func main() {
        if AppDelegate.isTestHost() {
            TestHostApp.main()
        } else {
            RoteApp.main()
        }
    }
}

struct RoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container: AppContainer = MainActor.assumeIsolated { AppContainer.shared }

    var body: some Scene {
        MenuBarExtra {
            ProgressPopoverView()
                .environment(container)
        } label: {
            Image(nsImage: MenuBarIcon.image(for: container.iconState))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(container)
        }
    }
}

/// The app XCTest launches to host the unit tests: the same delegate, whose test-host check keeps
/// the container from starting, and a scene that shows nothing.
struct TestHostApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

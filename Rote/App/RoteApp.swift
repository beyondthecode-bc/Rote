import SwiftUI

@main
struct RoteApp: App {
    var body: some Scene {
        MenuBarExtra("Rote", systemImage: "keyboard") {
            Text("Rote is starting up.")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}

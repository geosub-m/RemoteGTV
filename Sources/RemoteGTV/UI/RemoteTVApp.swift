import SwiftUI

@main
struct RemoteTVApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 320, height: 520) // Compact remote size
    }
}

import SwiftUI

@main
struct TwitchLauncherApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .defaultSize(width: 620, height: 540)
    }
}

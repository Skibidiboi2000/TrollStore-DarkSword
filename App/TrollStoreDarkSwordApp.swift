import SwiftUI

@main
struct TrollStoreDarkSwordApp: App {
    @StateObject private var coordinator = ContentCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
        }
    }
}

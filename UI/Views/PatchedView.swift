import SwiftUI

struct PatchedView: View {
    @EnvironmentObject private var coordinator: ContentCoordinator

    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            AppGridView()
                .tabItem {
                    Label("Apps", systemImage: "square.grid.3x3")
                }
                .tag(ContentCoordinator.Tab.apps)

            InstallView()
                .tabItem {
                    Label("Install", systemImage: "tray.and.arrow.down")
                }
                .tag(ContentCoordinator.Tab.install)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.2")
                }
                .tag(ContentCoordinator.Tab.settings)
        }
    }
}

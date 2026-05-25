import SwiftUI

struct PatchedView: View {
    var body: some View {
        TabView {
            AppGridView()
                .tabItem {
                    Label("Apps", systemImage: "square.grid.3x3.fill")
                }

            InstallView()
                .tabItem {
                    Label("Install", systemImage: "plus.circle")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}

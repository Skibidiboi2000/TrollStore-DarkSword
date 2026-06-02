import SwiftUI

struct PatchedView: View {
    @EnvironmentObject private var coordinator: ContentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            // Tab content
            ZStack {
                switch coordinator.selectedTab {
                case .home:
                    HomeView()
                case .apps:
                    AppGridView()
                case .install:
                    InstallView()
                case .activity:
                    ActivityView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom tab bar
            tabBar
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ContentCoordinator.Tab.allCases, id: \.self) { tab in
                Button {
                    coordinator.selectedTab = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 22))
                        Text(tab.label)
                            .font(.system(size: 10))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(coordinator.selectedTab == tab ? AppTheme.accentColor : AppTheme.labelTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(AppTheme.tabBarBackground)
        .background(Material.ultraThinMaterial)
        .overlay(alignment: .top) {
            AppTheme.separatorColor.opacity(0.24)
                .frame(height: 0.5)
        }
    }
}

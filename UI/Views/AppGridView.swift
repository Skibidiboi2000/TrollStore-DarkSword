import SwiftUI

struct AppGridView: View {
    @EnvironmentObject private var coordinator: ContentCoordinator
    @State private var viewModel: AppListViewModel?
    @State private var deleteConfirm: InstalledApp?
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.kernelHandle == nil {
                    notReadyView
                } else {
                    appListContent
                }
            }
            .onAppear {
                ensureViewModel()
                viewModel?.refresh()
            }
            .onChange(of: coordinator.kernelHandle) { _ in
                guard coordinator.kernelHandle != nil else { return }
                viewModel?.refresh()
            }
            .alert(item: $deleteConfirm) { app in
                Alert(
                    title: Text("Uninstall \(app.name)"),
                    message: Text("Are you sure you want to remove this app?"),
                    primaryButton: .destructive(Text("Uninstall")) {
                        Task { await viewModel?.uninstall(app) }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    // MARK: - Not Ready View

    private var notReadyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundColor(AppTheme.labelTertiary)
            Text("No Kernel Access")
                .font(.headline)
                .foregroundColor(AppTheme.labelSecondary)
            Text("Run the exploit first to gain kernel access.")
                .font(.body)
                .foregroundColor(AppTheme.labelTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - App List

    private var appListContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Apps")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                // Search bar
                searchField
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if let apps = viewModel?.filteredApps, apps.isEmpty {
                    emptyView
                } else if let apps = viewModel?.filteredApps {
                    AppTheme.sectionHeader("Installed")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    appCardList(apps: apps)
                        .padding(.horizontal, 20)
                }
            }
            Color.clear.frame(height: 20)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundColor(AppTheme.labelTertiary)

            TextField("Search apps", text: Binding(
                get: { viewModel?.searchText ?? "" },
                set: { viewModel?.searchText = $0 }
            ))
            .font(.body)
            .foregroundColor(.primary)
            .autocorrectionDisabled()
        }
        .padding(10)
        .background(AppTheme.searchBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.smallCornerRadius))
    }

    private func appCardList(apps: [InstalledApp]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(apps.enumerated()), id: \.offset) { index, app in
                NavigationLink(destination: AppDetailView(app: app)) {
                    AppRowView(app: app)
                }
                .buttonStyle(.plain)

                if index < apps.count - 1 {
                    AppTheme.separatorColor
                        .frame(height: 0.5)
                        .padding(.leading, 78)
                }
            }
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 36))
                .foregroundColor(AppTheme.labelTertiary)
            Text("No Apps Installed")
                .font(.headline)
                .foregroundColor(AppTheme.labelSecondary)
            Text("Tap Install to add your first app.")
                .font(.body)
                .foregroundColor(AppTheme.labelTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Helpers

    private func ensureViewModel() {
        guard viewModel == nil, let handle = coordinator.kernelHandle else { return }
        let persistence = PersistenceService()
        let remoteCall = RemoteCallEngine(kernelHandle: handle)
        let springBoard = SpringBoardExecutor(remoteCall: remoteCall)
        viewModel = AppListViewModel(
            persistence: persistence,
            springBoard: springBoard,
            remoteCall: remoteCall
        )
    }
}

// MARK: - App Row

private struct AppRowView: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 14) {
            iconView

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(app.bundleID)
                    .font(.caption)
                    .foregroundColor(AppTheme.labelTertiary)
                    .fontDesign(.monospaced)
                    .lineLimit(1)
            }

            Spacer()

            Text("v\(app.version)")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var iconView: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(iconGradient)
            .frame(width: 52, height: 52)
            .overlay(
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundColor(.white)
            )
    }

    private var iconGradient: LinearGradient {
        let gradients: [LinearGradient] = [
            LinearGradient(colors: [
                Color(red: 10/255, green: 77/255, blue: 153/255),
                Color(red: 91/255, green: 26/255, blue: 153/255)
            ], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [
                Color(red: 255/255, green: 159/255, blue: 10/255),
                Color(red: 255/255, green: 55/255, blue: 95/255)
            ], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [
                Color(red: 48/255, green: 209/255, blue: 88/255),
                Color(red: 64/255, green: 200/255, blue: 224/255)
            ], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [
                Color(red: 191/255, green: 90/255, blue: 242/255),
                Color(red: 88/255, green: 86/255, blue: 214/255)
            ], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [
                Color(red: 255/255, green: 55/255, blue: 95/255),
                Color(red: 255/255, green: 159/255, blue: 10/255)
            ], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [
                Color(red: 100/255, green: 210/255, blue: 255/255),
                Color(red: 10/255, green: 132/255, blue: 255/255)
            ], startPoint: .topLeading, endPoint: .bottomTrailing),
        ]
        let hash = abs(app.bundleID.hashValue)
        return gradients[hash % gradients.count]
    }

    private var iconName: String {
        switch app.bundleID {
        case _ where app.bundleID.contains("safari"): return "safari"
        case _ where app.bundleID.contains("photo"): return "photo"
        case _ where app.bundleID.contains("music"): return "music.note"
        case _ where app.bundleID.contains("video"): return "video"
        case _ where app.bundleID.contains("game"): return "gamecontroller"
        case _ where app.bundleID.contains("chat") || app.bundleID.contains("message"): return "message"
        default: return "app.fill"
        }
    }
}

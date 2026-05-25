import SwiftUI

struct AppGridView: View {
    @Environment(ContentCoordinator.self) private var coordinator
    @State private var viewModel: AppListViewModel?

    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(viewModel?.filteredApps ?? []) { app in
                        NavigationLink(destination: AppDetailView(app: app)) {
                            VStack(spacing: 8) {
                                Image(systemName: iconName(for: app))
                                    .font(.system(size: 36))
                                    .foregroundColor(.accentColor)
                                    .frame(width: 60, height: 60)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(14)

                                Text(app.name)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.primary)
                            }
                            .frame(width: 80)
                            .contextMenu {
                                Button("Details", systemImage: "info.circle") {
                                    // Navigation handled by NavigationLink
                                }
                                Button("Uninstall", systemImage: "trash", role: .destructive) {
                                    Task { await viewModel?.uninstall(app) }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Apps")
            .searchable(text: Binding(
                get: { viewModel?.searchText ?? "" },
                set: { viewModel?.searchText = $0 }
            ))
            .refreshable {
                viewModel?.refresh()
            }
            .overlay {
                if coordinator.kernelHandle == nil {
                    ContentUnavailableView(
                        "No Kernel Access",
                        systemImage: "lock.shield",
                        description: Text("Run the exploit first to gain kernel access.")
                    )
                } else if (viewModel?.installedApps ?? []).isEmpty {
                    ContentUnavailableView(
                        "No Apps Installed",
                        systemImage: "square.grid.3x3",
                        description: Text("Tap Install to add your first app.")
                    )
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                if let handle = coordinator.kernelHandle {
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
            viewModel?.refresh()
        }
    }

    private func iconName(for app: InstalledApp) -> String {
        switch app.bundleID {
        case _ where app.bundleID.contains("safari"): return "safari"
        case _ where app.bundleID.contains("photo"): return "photo"
        case _ where app.bundleID.contains("music"): return "music.note"
        default: return "app.fill"
        }
    }
}

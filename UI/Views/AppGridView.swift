import SwiftUI

struct AppGridView: View {
    @EnvironmentObject private var coordinator: ContentCoordinator
    @State private var viewModel: AppListViewModel?
    @State private var deleteConfirm: InstalledApp?

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.kernelHandle == nil {
                    notReadyView
                } else {
                    appListContent
                }
            }
            .navigationTitle("Apps")
            .toolbar {
                if coordinator.kernelHandle != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            coordinator.selectedTab = .install
                        } label: {
                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                        }
                    }
                }
            }
        }
        .onAppear {
            ensureViewModel()
            viewModel?.refresh()
        }
        .onChange(of: coordinator.kernelHandle) { newHandle in
            guard newHandle != nil else { return }
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

    // MARK: - Not Ready View

    private var notReadyView: some View {
        ContentUnavailableView(
            "No Kernel Access",
            systemImage: "lock.shield",
            description: Text("Run the exploit first to gain kernel access.")
        )
    }

    // MARK: - App List

    private var appListContent: some View {
        Group {
            if let apps = viewModel?.filteredApps, apps.isEmpty {
                emptyView
            } else {
                List {
                    ForEach(viewModel?.filteredApps ?? []) { app in
                        NavigationLink(destination: AppDetailView(app: app)) {
                            AppRowView(app: app)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteConfirm = app
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: Binding(
                    get: { viewModel?.searchText ?? "" },
                    set: { viewModel?.searchText = $0 }
                ), prompt: "Search apps")
                .refreshable {
                    viewModel?.refresh()
                }
            }
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        ContentUnavailableView(
            "No Apps Installed",
            systemImage: "square.grid.3x3",
            description: Text("Tap Install to add your first app.")
        )
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
                    .lineLimit(1)

                Text(app.bundleID)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("v\(app.version)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var iconView: some View {
        RoundedRectangle(cornerRadius: 12)
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
            LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
        ]
        // Deterministic selection based on bundleID hash
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

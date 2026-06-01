import SwiftUI

@MainActor
public final class AppListViewModel: ObservableObject {
    @Published public var installedApps: [InstalledApp] = []
    @Published public var searchText = ""

    private let persistence: PersistenceService
    private let springBoard: SpringBoardExecutor
    private let remoteCall: RemoteCallEngine

    public init(persistence: PersistenceService, springBoard: SpringBoardExecutor, remoteCall: RemoteCallEngine) {
        self.persistence = persistence
        self.springBoard = springBoard
        self.remoteCall = remoteCall
    }

    public func refresh() {
        installedApps = persistence.loadInstalledApps().filter { app in
            FileManager.default.fileExists(atPath: app.path)
        }
    }

    /// Scan /Applications/ for .app bundles not in the installed list and add them.
    public func rescanInstalledApps() {
        installedApps = persistence.rescanApplicationsDirectory()
    }

    public var filteredApps: [InstalledApp] {
        guard !searchText.isEmpty else { return installedApps }
        return installedApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    public func uninstall(_ app: InstalledApp) async {
        do {
            try await springBoard.uninstallAppBundle(bundleID: app.bundleID)
            persistence.removeApp(bundleID: app.bundleID)
            refresh()
        } catch {
            LogManager.shared.append("Uninstall failed: \(error)", tag: "AppList")
        }
    }
}

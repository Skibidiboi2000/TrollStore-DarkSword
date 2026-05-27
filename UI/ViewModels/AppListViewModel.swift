import SwiftUI

@MainActor
@Observable
public final class AppListViewModel {
    public var installedApps: [InstalledApp] = []
    public var searchText = ""

    private let persistence: PersistenceService
    private let springBoard: SpringBoardExecutor
    private let remoteCall: RemoteCallEngine

    public init(persistence: PersistenceService, springBoard: SpringBoardExecutor, remoteCall: RemoteCallEngine) {
        self.persistence = persistence
        self.springBoard = springBoard
        self.remoteCall = remoteCall
    }

    public func refresh() {
        installedApps = persistence.loadInstalledApps()
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

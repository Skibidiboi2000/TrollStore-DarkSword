import Foundation

public final class PersistenceService: @unchecked Sendable {
    private let fileManager: FileManager
    private let appsFile: URL
    private let lock = NSLock()

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.appsFile = docs.appendingPathComponent("installed_apps.json")
    }

    /// Load the list of installed apps from persistent storage.
    public func loadInstalledApps() -> [InstalledApp] {
        guard let data = try? Data(contentsOf: appsFile) else { return [] }
        do {
            return try JSONDecoder().decode([InstalledApp].self, from: data)
        } catch {
            LogManager.shared.append("Failed to decode installed apps: \(error.localizedDescription)", tag: "Persistence")
            return []
        }
    }

    /// Save the complete list of installed apps to persistent storage.
    public func saveInstalledApps(_ apps: [InstalledApp]) {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        try? data.write(to: appsFile, options: .atomic)
    }

    /// Add a single app to the persistent list (replaces existing entry with same bundleID).
    public func addApp(_ app: InstalledApp) {
        lock.withLock {
            var apps = loadInstalledApps()
            apps.removeAll { $0.bundleID == app.bundleID }
            apps.append(app)
            saveInstalledApps(apps)
        }
    }

    /// Remove an app from the persistent list by bundle ID.
    public func removeApp(bundleID: String) {
        lock.withLock {
            var apps = loadInstalledApps()
            apps.removeAll { $0.bundleID == bundleID }
            saveInstalledApps(apps)
        }
    }
}

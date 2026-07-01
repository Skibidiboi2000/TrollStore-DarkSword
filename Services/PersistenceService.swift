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
        lock.withLock {
            _loadInstalledApps()
        }
    }

    private func _loadInstalledApps() -> [InstalledApp] {
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
        lock.withLock {
            _saveInstalledApps(apps)
        }
    }

    private func _saveInstalledApps(_ apps: [InstalledApp]) {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        try? data.write(to: appsFile, options: .atomic)
    }

    /// Add a single app to the persistent list (replaces existing entry with same bundleID).
    public func addApp(_ app: InstalledApp) {
        lock.withLock {
            var apps = _loadInstalledApps()
            apps.removeAll { $0.bundleID == app.bundleID }
            apps.append(app)
            _saveInstalledApps(apps)
        }
    }

    /// Remove an app from the persistent list by bundle ID.
    public func removeApp(bundleID: String) {
        lock.withLock {
            var apps = _loadInstalledApps()
            apps.removeAll { $0.bundleID == bundleID }
            _saveInstalledApps(apps)
        }
    }

    /// Scan /Applications/ for .app bundles not yet tracked and merge them in.
    /// Returns the merged list.
    @discardableResult
    public func rescanApplicationsDirectory() -> [InstalledApp] {
        lock.withLock {
            let fm = fileManager
            var apps = _loadInstalledApps()
            let existingIDs = Set(apps.map(\.bundleID))

            guard let contents = try? fm.contentsOfDirectory(atPath: "/Applications/") else { return apps }
            let appBundles = contents.filter { $0.hasSuffix(".app") }

            for bundleName in appBundles {
                let bundlePath = "/Applications/\(bundleName)"
                let infoPlistURL = URL(fileURLWithPath: bundlePath).appendingPathComponent("Info.plist")
                guard let infoData = try? Data(contentsOf: infoPlistURL),
                      let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
                      let bundleID = info["CFBundleIdentifier"] as? String,
                      !existingIDs.contains(bundleID) else { continue }

                let name = info["CFBundleDisplayName"] as? String
                    ?? info["CFBundleName"] as? String
                    ?? bundleName.replacingOccurrences(of: ".app", with: "")
                let version = info["CFBundleVersion"] as? String
                    ?? info["CFBundleShortVersionString"] as? String
                    ?? "1.0"
                let executable = info["CFBundleExecutable"] as? String ?? ""
                let installDate = (try? fm.attributesOfItem(atPath: bundlePath)[.modificationDate] as? Date) ?? Date()

                let app = InstalledApp(
                    name: name,
                    bundleID: bundleID,
                    version: version,
                    installDate: installDate,
                    path: bundlePath,
                    iconPath: nil,
                    executableName: executable
                )
                apps.append(app)
            }
            _saveInstalledApps(apps)
            return apps
        }
    }
}

import Foundation

public struct InstalledApp: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let bundleID: String
    public let version: String
    public let installDate: Date
    public let path: String
    public let iconPath: String?
    public let executableName: String

    public init(
        name: String,
        bundleID: String,
        version: String,
        installDate: Date = Date(),
        path: String,
        iconPath: String?,
        executableName: String
    ) {
        self.id = bundleID
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.installDate = installDate
        self.path = path
        self.iconPath = iconPath
        self.executableName = executableName
    }
}

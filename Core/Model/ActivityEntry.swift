import Foundation

public struct ActivityEntry: Identifiable, Sendable {
    public let id = UUID()
    public let message: String
    public let date: Date
    public let type: ActivityType

    public enum ActivityType: Sendable {
        case success
        case info
        case error
        case warning
        case action
    }

    public init(message: String, type: ActivityType = .info, date: Date = Date()) {
        self.message = message
        self.type = type
        self.date = date
    }
}

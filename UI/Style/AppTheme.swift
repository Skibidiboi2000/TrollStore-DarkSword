import SwiftUI

public enum AppTheme {
    public static let accentColor = Color.blue
    public static let successColor = Color.green
    public static let failureColor = Color.red
    public static let cardBackground = Color(.systemGray6)
    public static let gridSpacing: CGFloat = 16
    public static let cornerRadius: CGFloat = 14

    public static let springAnimation = Animation.spring(
        response: 0.4,
        dampingFraction: 0.7,
        blendDuration: 0.2
    )

    public static let easeOutAnimation = Animation.easeOut(duration: 0.3)

    @MainActor public static func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    @MainActor public static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

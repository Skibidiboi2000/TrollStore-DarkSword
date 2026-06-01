import SwiftUI

public enum AppTheme {
    // MARK: - Colors
    public static let accentColor = Color.blue
    public static let successColor = Color.green
    public static let failureColor = Color.red
    public static let warningColor = Color.orange
    public static let cardBackground = Color(.systemGray6)

    // MARK: - Gradients
    public static let primaryGradient = LinearGradient(
        gradient: Gradient(colors: [Color(red: 0.05, green: 0.3, blue: 0.6), Color(red: 0.4, green: 0.1, blue: 0.6)]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let accentGradient = LinearGradient(
        gradient: Gradient(colors: [Color.blue, Color.purple]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let successGradient = LinearGradient(
        gradient: Gradient(colors: [Color.green, Color.teal]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let warningGradient = LinearGradient(
        gradient: Gradient(colors: [Color.orange, Color.yellow]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Layout Constants
    public static let gridSpacing: CGFloat = 16
    public static let cornerRadius: CGFloat = 14
    public static let iconSize: CGFloat = 88
    public static let buttonHeight: CGFloat = 52

    // MARK: - Animations
    public static let springAnimation = Animation.spring(
        response: 0.4,
        dampingFraction: 0.7,
        blendDuration: 0.2
    )

    public static let easeOutAnimation = Animation.easeOut(duration: 0.3)

    public static var springTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.92)),
            removal: .opacity.combined(with: .scale(scale: 1.05))
        )
    }

    // MARK: - Haptics
    @MainActor public static func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    @MainActor public static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    // MARK: - View Modifiers
    public static func gradientIcon(systemName: String, width: CGFloat = 60, height: CGFloat = 60) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(accentGradient)
            .frame(width: width, height: height)
            .overlay(
                Image(systemName: systemName)
                    .font(.title2)
                    .foregroundColor(.white)
            )
    }
}

import SwiftUI
import UIKit

public enum AppTheme {
    // MARK: - iOS 26 HIG Colors
    public static let accentColor = Color(red: 10/255, green: 132/255, blue: 255/255)
    public static let successColor = Color(red: 48/255, green: 209/255, blue: 88/255)
    public static let failureColor = Color(red: 255/255, green: 69/255, blue: 58/255)
    public static let warningColor = Color(red: 255/255, green: 214/255, blue: 10/255)
    public static let orangeAccent = Color(red: 255/255, green: 159/255, blue: 10/255)
    public static let purpleAccent = Color(red: 191/255, green: 90/255, blue: 242/255)
    public static let tealAccent = Color(red: 100/255, green: 210/255, blue: 255/255)

    // MARK: - Card & Material Colors
    public static let cardBackground = Color(red: 28/255, green: 28/255, blue: 30/255).opacity(0.75)
    public static let secondaryCardBackground = Color(red: 44/255, green: 44/255, blue: 46/255).opacity(0.75)
    public static let separatorColor = Color(red: 84/255, green: 84/255, blue: 88/255).opacity(0.36)
    public static let thinSeparatorColor = Color(red: 84/255, green: 84/255, blue: 88/255).opacity(0.18)
    public static let labelSecondary = Color(red: 142/255, green: 142/255, blue: 147/255)
    public static let labelTertiary = Color(red: 99/255, green: 99/255, blue: 99/255)
    public static let tabBarBackground = Color(red: 22/255, green: 22/255, blue: 24/255).opacity(0.92)
    public static let searchBackground = Color(red: 118/255, green: 118/255, blue: 128/255).opacity(0.12)

    // MARK: - Layout Constants
    public static let cardCornerRadius: CGFloat = 20
    public static let largeCornerRadius: CGFloat = 24
    public static let mediumCornerRadius: CGFloat = 14
    public static let smallCornerRadius: CGFloat = 10
    public static let iconSize: CGFloat = 52
    public static let buttonHeight: CGFloat = 50
    public static let gridSpacing: CGFloat = 16

    // MARK: - Animations
    public static let springAnimation = Animation.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)
    public static let easeOutAnimation = Animation.easeOut(duration: 0.25)

    // MARK: - Haptics
    @MainActor public static func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    @MainActor public static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    // MARK: - Card Group Modifier
    public static func cardGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
    }

    /// Apple-style section header (uppercase, secondary, 13px)
    public static func sectionHeader(_ title: String, color: Color = labelSecondary) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(color)
            .textCase(.uppercase)
            .padding(EdgeInsets(top: 20, leading: 20, bottom: 6, trailing: 20))
    }

    /// Apple-style danger section header
    public static func dangerSectionHeader(_ title: String) -> some View {
        sectionHeader(title, color: failureColor)
    }

    /// Grouped list row with label + value
    public static func listRow<Label: View, Value: View>(
        @ViewBuilder label: () -> Label,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(spacing: 12) {
            label()
                .font(.body)
                .foregroundColor(.secondary)
                .frame(minWidth: 80, alignment: .leading)
            Spacer()
            value()
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }
}

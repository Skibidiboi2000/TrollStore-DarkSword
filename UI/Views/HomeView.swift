import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var coordinator: ContentCoordinator
    @State private var apps: [InstalledApp] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                // Status summary
                VStack(spacing: 0) {
                    Text("TrollStore")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                statusCard
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                AppTheme.sectionHeader("System")
                    .frame(maxWidth: .infinity, alignment: .leading)

                systemSection
                    .padding(.horizontal, 20)

                AppTheme.sectionHeader("Installed Apps")
                    .frame(maxWidth: .infinity, alignment: .leading)

                installedAppsPreview
                    .padding(.horizontal, 20)

                AppTheme.sectionHeader("Recent Activity")
                    .frame(maxWidth: .infinity, alignment: .leading)

                recentActivity
                    .padding(.horizontal, 20)

                Color.clear.frame(height: 20)
            }
        }
        .onAppear {
            apps = PersistenceService().loadInstalledApps()
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppTheme.successColor)
                        .frame(width: 8, height: 8)
                    Text("Kernel Active")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("DarkSword v1.0")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    // MARK: - System Section

    private var systemSection: some View {
        VStack(spacing: 0) {
            systemRow(
                icon: "lock.shield.fill",
                color: AppTheme.accentColor,
                label: "Kernel Patches",
                value: "Applied",
                valueColor: AppTheme.successColor
            )

            AppTheme.thinSeparatorColor
                .frame(height: 0.5)
                .padding(.leading, 52)

            systemRow(
                icon: "bell.fill",
                color: AppTheme.successColor,
                label: "Sandbox",
                value: "Cleared",
                valueColor: AppTheme.successColor
            )

            AppTheme.thinSeparatorColor
                .frame(height: 0.5)
                .padding(.leading, 52)

            systemRow(
                icon: "lock.open.fill",
                color: AppTheme.purpleAccent,
                label: "AMFI",
                value: "Disabled",
                valueColor: AppTheme.successColor
            )
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    private func systemRow(icon: String, color: Color, label: String, value: String, valueColor: Color) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7)
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                )

            Text(label)
                .font(.body)

            Spacer()

            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(valueColor)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    // MARK: - Installed Apps Preview

    private var installedAppsPreview: some View {
        VStack(spacing: 0) {
            if apps.isEmpty {
                HStack {
                    Text("No apps installed")
                        .font(.body)
                        .foregroundColor(AppTheme.labelTertiary)
                    Spacer()
                }
                .padding(16)
            } else {
                ForEach(Array(apps.prefix(4).enumerated()), id: \.offset) { _, app in
                    NavigationLink(destination: AppDetailView(app: app)) {
                        AppRowContent(app: app)
                    }
                    .buttonStyle(.plain)

                    if app.bundleID != apps.prefix(4).last?.bundleID {
                        AppTheme.separatorColor
                            .frame(height: 0.5)
                            .padding(.leading, 78)
                    }
                }
            }
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    // MARK: - Recent Activity

    private var recentActivity: some View {
        VStack(spacing: 0) {
            let recent = coordinator.activityEntries.prefix(5)
            if recent.isEmpty {
                HStack {
                    Text("No recent activity")
                        .font(.body)
                        .foregroundColor(AppTheme.labelTertiary)
                    Spacer()
                }
                .padding(16)
            } else {
                ForEach(Array(recent.enumerated()), id: \.offset) { _, entry in
                    activityRow(entry: entry)
                    if entry.id != recent.last?.id {
                        AppTheme.thinSeparatorColor
                            .frame(height: 0.5)
                            .padding(.leading, 52)
                    }
                }
            }
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    private func activityRow(entry: ActivityEntry) -> some View {
        HStack(spacing: 12) {
            iconForActivityType(entry.type)
                .frame(width: 28, height: 28)

            Text(entry.message)
                .font(.body)
                .lineLimit(1)

            Spacer()

            Text(entry.date, style: .relative)
                .font(.caption)
                .foregroundColor(AppTheme.labelTertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    private func iconForActivityType(_ type: ActivityEntry.ActivityType) -> some View {
        let config: (color: Color, icon: String) = {
            switch type {
            case .success: return (AppTheme.successColor, "checkmark")
            case .info:    return (AppTheme.accentColor, "info")
            case .error:   return (AppTheme.failureColor, "exclamationmark")
            case .warning: return (AppTheme.orangeAccent, "exclamationmark.triangle")
            case .action:  return (AppTheme.purpleAccent, "arrow.triangle.2.circlepath")
            }
        }()

        return RoundedRectangle(cornerRadius: 7)
            .fill(config.color.opacity(0.12))
            .overlay(
                Image(systemName: config.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(config.color)
            )
    }
}

// MARK: - App Row Content (reusable)

struct AppRowContent: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 14) {
            iconView

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(app.bundleID)
                    .font(.caption)
                    .foregroundColor(AppTheme.labelTertiary)
                    .fontDesign(.monospaced)
                    .lineLimit(1)
            }

            Spacer()

            Text("v\(app.version)")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var iconView: some View {
        RoundedRectangle(cornerRadius: 14)
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
            LinearGradient(colors: [
                Color(red: 10/255, green: 77/255, blue: 153/255),
                Color(red: 91/255, green: 26/255, blue: 153/255)
            ], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [
                Color(red: 255/255, green: 159/255, blue: 10/255),
                Color(red: 255/255, green: 55/255, blue: 95/255)
            ], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [
                Color(red: 48/255, green: 209/255, blue: 88/255),
                Color(red: 64/255, green: 200/255, blue: 224/255)
            ], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [
                Color(red: 191/255, green: 90/255, blue: 242/255),
                Color(red: 88/255, green: 86/255, blue: 214/255)
            ], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [
                Color(red: 255/255, green: 55/255, blue: 95/255),
                Color(red: 255/255, green: 159/255, blue: 10/255)
            ], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [
                Color(red: 100/255, green: 210/255, blue: 255/255),
                Color(red: 10/255, green: 132/255, blue: 255/255)
            ], startPoint: .topLeading, endPoint: .bottomTrailing),
        ]
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

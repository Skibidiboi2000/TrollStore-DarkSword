import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var coordinator: ContentCoordinator

    var body: some View {
        NavigationStack {
            ScrollView {
                Text("Activity")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                AppTheme.sectionHeader("Events")
                    .frame(maxWidth: .infinity, alignment: .leading)

                eventsSection
                    .padding(.horizontal, 20)

                AppTheme.sectionHeader("Live Log")
                    .frame(maxWidth: .infinity, alignment: .leading)

                logSection
                    .padding(.horizontal, 20)

                Color.clear.frame(height: 20)
            }
        }
    }

    // MARK: - Events Section

    private var eventsSection: some View {
        VStack(spacing: 0) {
            if coordinator.activityEntries.isEmpty {
                HStack {
                    Text("No activity yet")
                        .font(.body)
                        .foregroundColor(AppTheme.labelTertiary)
                    Spacer()
                }
                .padding(16)
            } else {
                ForEach(Array(coordinator.activityEntries.prefix(10).enumerated()), id: \.offset) { _, entry in
                    eventRow(entry: entry)
                    if entry.id != coordinator.activityEntries.prefix(10).last?.id {
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

    private func eventRow(entry: ActivityEntry) -> some View {
        HStack(spacing: 12) {
            eventIcon(entry.type)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.body)
                    .lineLimit(1)

                Text(entry.date, style: .relative)
                    .font(.caption)
                    .foregroundColor(AppTheme.labelTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }

    private func eventIcon(_ type: ActivityEntry.ActivityType) -> some View {
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
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: config.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(config.color)
            )
    }

    // MARK: - Log Section

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if coordinator.exploitLog.isEmpty {
                Text("No log entries")
                    .font(.caption)
                    .foregroundColor(AppTheme.labelTertiary)
                    .fontDesign(.monospaced)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(coordinator.exploitLog.suffix(20).enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundColor(logColor(for: entry))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.mediumCornerRadius))
    }

    private func logColor(for line: String) -> Color {
        if line.contains("✓") || line.contains("granted") || line.contains("SUCCEEDED") {
            return AppTheme.successColor
        }
        if line.contains("FAILED") || line.contains("failed") || line.contains("error") {
            return AppTheme.failureColor
        }
        if line.contains("Racing") || line.contains("warning") {
            return AppTheme.orangeAccent
        }
        if line.contains("initialized") || line.contains("resolved") || line.contains("ready") {
            return AppTheme.tealAccent
        }
        return AppTheme.labelSecondary
    }
}

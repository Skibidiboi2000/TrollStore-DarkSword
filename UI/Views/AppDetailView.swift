import SwiftUI

struct AppDetailView: View {
    @EnvironmentObject private var coordinator: ContentCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var confirmUninstall = false

    let app: InstalledApp

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header card
                headerCard
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                AppTheme.sectionHeader("Info")
                    .frame(maxWidth: .infinity, alignment: .leading)

                infoCard
                    .padding(.horizontal, 20)

                AppTheme.sectionHeader("Actions")
                    .frame(maxWidth: .infinity, alignment: .leading)

                actionsCard
                    .padding(.horizontal, 20)

                Color.clear.frame(height: 20)
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Uninstall \(app.name)?", isPresented: $confirmUninstall) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive, action: uninstallApp)
        } message: {
            Text("This will remove the app and its data.")
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 18)
                .fill(appIconGradient)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: appIconName)
                        .font(.title)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(app.bundleID)
                    .font(.caption)
                    .foregroundColor(AppTheme.labelTertiary)
                    .fontDesign(.monospaced)

                Text("v\(app.version)")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    // MARK: - Info Card

    private var infoCard: some View {
        VStack(spacing: 0) {
            infoRow(label: "Bundle ID", value: app.bundleID, mono: true)
            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 16)
            infoRow(label: "Version", value: app.version)
            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 16)
            infoRow(label: "Executable", value: app.executableName)
            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 16)
            infoRow(label: "Installed", value: app.installDate.formatted(date: .abbreviated, time: .shortened))
            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 16)
            infoRow(label: "Path", value: app.path, mono: true, small: true)
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    private func infoRow(label: String, value: String, mono: Bool = false, small: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(minWidth: 70, alignment: .leading)
            Spacer()
            Text(value)
                .font(mono || small ? .caption : .body)
                .fontDesign(mono ? .monospaced : .default)
                .foregroundColor(small ? AppTheme.labelSecondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    // MARK: - Actions Card

    private var actionsCard: some View {
        VStack(spacing: 10) {
            Button(action: launchApp) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.body)
                    Text("Launch App")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.accentColor)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button(action: { confirmUninstall = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.body)
                    Text("Uninstall")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.clear)
                .foregroundColor(AppTheme.failureColor)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppTheme.failureColor.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var appIconGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 10/255, green: 77/255, blue: 153/255),
                Color(red: 91/255, green: 26/255, blue: 153/255)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var appIconName: String {
        switch app.bundleID {
        case _ where app.bundleID.contains("safari"): return "safari"
        case _ where app.bundleID.contains("photo"): return "photo"
        default: return "app.fill"
        }
    }

    private func launchApp() {
        guard let handle = coordinator.kernelHandle else { return }
        let remoteCall = RemoteCallEngine(kernelHandle: handle)
        let springBoard = SpringBoardExecutor(remoteCall: remoteCall)

        Task {
            do {
                try await springBoard.launchApp(bundleID: app.bundleID)
                LogManager.shared.append("Launched \(app.bundleID) ✓", tag: "AppDetail")
            } catch {
                LogManager.shared.append("Launch failed: \(error)", tag: "AppDetail")
            }
        }
    }

    private func uninstallApp() {
        guard let handle = coordinator.kernelHandle else { return }
        let remoteCall = RemoteCallEngine(kernelHandle: handle)
        let springBoard = SpringBoardExecutor(remoteCall: remoteCall)
        let persistence = PersistenceService()

        Task {
            do {
                try await springBoard.uninstallAppBundle(bundleID: app.bundleID)
                persistence.removeApp(bundleID: app.bundleID)
                LogManager.shared.append("Uninstalled \(app.bundleID) ✓", tag: "AppDetail")
                await MainActor.run { dismiss() }
            } catch {
                LogManager.shared.append("Uninstall failed: \(error)", tag: "AppDetail")
            }
        }
    }
}

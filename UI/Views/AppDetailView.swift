import SwiftUI

struct AppDetailView: View {
    @EnvironmentObject private var coordinator: ContentCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var confirmUninstall = false

    let app: InstalledApp

    var body: some View {
        List {
            // Header
            Section {
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(appIconGradient)
                        .frame(width: 72, height: 72)
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
                            .foregroundColor(.secondary)
                            .fontDesign(.monospaced)
                        Text("v\(app.version)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            // Info
            Section("Info") {
                LabeledContent("Bundle ID", value: app.bundleID)
                LabeledContent("Version", value: app.version)
                LabeledContent("Executable", value: app.executableName)
                LabeledContent("Installed", value: app.installDate.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Path", value: app.path)
                    .font(.caption)
                    .fontDesign(.monospaced)
            }

            // Actions
            Section {
                Button(action: launchApp) {
                    Label("Launch App", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive, action: { confirmUninstall = true }) {
                    Label("Uninstall", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
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

    private var appIconGradient: LinearGradient {
        LinearGradient(
            colors: [.blue, .purple],
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

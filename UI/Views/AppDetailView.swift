import SwiftUI

struct AppDetailView: View {
    @Environment(ContentCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    let app: InstalledApp

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "app.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                        .frame(width: 72, height: 72)
                        .background(Color(.systemGray6))
                        .cornerRadius(16)

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

            Section("Info") {
                LabeledContent("Bundle ID", value: app.bundleID)
                LabeledContent("Version", value: app.version)
                LabeledContent("Executable", value: app.executableName)
                LabeledContent("Installed", value: app.installDate.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Path", value: app.path)
                    .font(.caption)
                    .fontDesign(.monospaced)
            }

            Section {
                Button(action: { launchApp() }) {
                    Label("Launch App", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive, action: { uninstallApp() }) {
                    Label("Uninstall", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
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

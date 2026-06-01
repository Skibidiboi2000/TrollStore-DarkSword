import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var coordinator: ContentCoordinator
    @AppStorage("darkMode") private var isDarkMode = false
    @State private var exportError: String?
    @State private var exportData: Data?
    @State private var confirmUninstallAll = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Kernel
                Section {
                    Button(action: rePatchKernel) {
                        Label {
                            Text("Re-patch Kernel")
                        } icon: {
                            settingsIcon(systemName: "bolt.shield.fill", color: .blue)
                        }
                    }

                    Button(action: { Task { await reregisterAll() } }) {
                        Label {
                            Text("Re-register All Apps")
                        } icon: {
                            settingsIcon(systemName: "arrow.triangle.2.circlepath", color: .purple)
                        }
                    }

                    Button(action: { Task { await rescanApps() } }) {
                        Label {
                            Text("Rescan Installed Apps")
                        } icon: {
                            settingsIcon(systemName: "magnifyingglass.circle", color: .blue)
                        }
                    }
                } header: {
                    Text("Kernel")
                }

                // MARK: - General
                Section {
                    HStack {
                        Label {
                            Text("Dark Mode")
                        } icon: {
                            settingsIcon(systemName: "moon.fill", color: .purple)
                        }
                        Spacer()
                        Toggle("", isOn: $isDarkMode)
                            .labelsHidden()
                    }

                    HStack {
                        Label {
                            Text("Persist Installation")
                        } icon: {
                            settingsIcon(systemName: "square.and.arrow.down", color: .orange)
                        }
                        Spacer()
                        Toggle("", isOn: $coordinator.persistInstallation)
                            .labelsHidden()
                    }
                } header: {
                    Text("General")
                }

                // MARK: - Data
                Section {
                    if let exportError {
                        Label(exportError, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                    if let exportData {
                        ShareLink(item: exportData, preview: .init("Installed Apps")) {
                            Label {
                                Text("Export App List")
                            } icon: {
                                settingsIcon(systemName: "square.and.arrow.up", color: .green)
                            }
                        }
                    }
                } header: {
                    Text("Data")
                }
                .task {
                    guard exportData == nil else { return }
                    do {
                        exportData = try JSONEncoder().encode(PersistenceService().loadInstalledApps())
                    } catch {
                        exportError = "Export failed: \(error.localizedDescription)"
                    }
                }

                // MARK: - Diagnostics
                Section {
                    NavigationLink(destination: ExploitLogView()) {
                        Label {
                            Text("Exploit Log")
                        } icon: {
                            settingsIcon(systemName: "list.bullet.rectangle", color: .gray)
                        }
                    }

                    NavigationLink(destination: AboutView()) {
                        Label {
                            Text("About")
                        } icon: {
                            settingsIcon(systemName: "info.circle", color: .blue)
                        }
                    }
                } header: {
                    Text("Diagnostics")
                }

                // MARK: - Danger Zone
                Section {
                    Button(role: .destructive, action: { confirmUninstallAll = true }) {
                        Label("Uninstall All Apps", systemImage: "trash")
                    }
                } header: {
                    Text("Danger Zone")
                }
            }
            .navigationTitle("Settings")
        }
        .alert("Uninstall All Apps?", isPresented: $confirmUninstallAll) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall All", role: .destructive) {
                Task { await uninstallAll() }
            }
        } message: {
            Text("This will remove ALL installed apps and their data. This action cannot be undone.")
        }
    }

    private func settingsIcon(systemName: String, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(color)
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            )
    }

    // MARK: - Actions

    private func rePatchKernel() {
        guard let handle = coordinator.kernelHandle, ds_is_ready() else {
            LogManager.shared.append("No valid kernel handle — re-run exploit first", tag: "Settings")
            return
        }
        let kernelBase = XPFWrapper.findKernelBase()
        guard kernelBase > 0 else {
            LogManager.shared.append("Kernel base resolution failed — cannot re-patch", tag: "Settings")
            return
        }
        let patcher = KernelPatcher(handle: handle, kernelBase: kernelBase)
        if patcher.applyAll() {
            LogManager.shared.append("Kernel re-patched ✓", tag: "Settings")
        } else {
            LogManager.shared.append("Kernel re-patch failed", tag: "Settings")
        }
    }

    private func reregisterAll() async {
        guard let handle = coordinator.kernelHandle, ds_is_ready() else {
            LogManager.shared.append("No valid kernel handle — re-run exploit first", tag: "Settings")
            return
        }
        let remoteCall = RemoteCallEngine(kernelHandle: handle)
        let springBoard = SpringBoardExecutor(remoteCall: remoteCall)
        let persistence = PersistenceService()
        let apps = persistence.loadInstalledApps()
        LogManager.shared.append("Re-registering \(apps.count) apps via uicache -r", tag: "Settings")
        guard let pid = springBoard.springBoardPID else {
            LogManager.shared.append("SpringBoard not found — cannot re-register", tag: "Settings")
            return
        }
        _ = try? await remoteCall.execute(inProcess: pid, command: "/usr/bin/uicache -r")
        LogManager.shared.append("Re-registration complete", tag: "Settings")
    }

    private func rescanApps() async {
        let count = PersistenceService().rescanApplicationsDirectory().count
        LogManager.shared.append("Rescanned /Applications/ — \(count) apps tracked", tag: "Settings")
    }

    private func uninstallAll() async {
        guard let handle = coordinator.kernelHandle, ds_is_ready() else {
            LogManager.shared.append("No valid kernel handle — re-run exploit first", tag: "Settings")
            return
        }
        let persistence = PersistenceService()
        let apps = persistence.loadInstalledApps()
        guard !apps.isEmpty else {
            LogManager.shared.append("No apps to uninstall", tag: "Settings")
            return
        }
        let remoteCall = RemoteCallEngine(kernelHandle: handle)
        let springBoard = SpringBoardExecutor(remoteCall: remoteCall)
        for app in apps {
            do {
                try await springBoard.uninstallAppBundle(bundleID: app.bundleID)
                persistence.removeApp(bundleID: app.bundleID)
                LogManager.shared.append("Uninstalled \(app.bundleID)", tag: "Settings")
            } catch {
                LogManager.shared.append("Uninstall failed for \(app.bundleID): \(error)", tag: "Settings")
            }
        }
        LogManager.shared.append("Uninstall all complete", tag: "Settings")
    }
}

// MARK: - Exploit Log View

struct ExploitLogView: View {
    @EnvironmentObject private var coordinator: ContentCoordinator

    var body: some View {
        ScrollView {
            if coordinator.exploitLog.isEmpty {
                ContentUnavailableView(
                    "No Log Entries",
                    systemImage: "doc.text",
                    description: Text("Run the exploit to generate log entries.")
                )
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(coordinator.exploitLog.enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontDesign(.monospaced)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .navigationTitle("Exploit Log")
        .toolbar {
            if let logURL = LogManager.shared.currentLogURL {
                ShareLink(item: logURL, preview: SharePreview("Exploit Log")) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }
}

// MARK: - About View

struct AboutView: View {
    private let device = DeviceInfo.current

    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: "1.0")
                LabeledContent("Device", value: device.modelIdentifier)
                LabeledContent("iOS", value: device.systemVersion)
                LabeledContent("Chip", value: device.cpuFamilyName)
                LabeledContent("PAC", value: device.isPACSupported ? "Yes" : "No")
                LabeledContent("Exploit", value: "DarkSword")
            }

            Section("Credits") {
                Text("DarkSword by rooootdev")
                Text("ChOma by khanhduytran0")
                Text("XPF from Fugu14 by Linus Henze")
                Text("RemoteCall pattern from LARA")
            }
        }
        .navigationTitle("About")
    }
}

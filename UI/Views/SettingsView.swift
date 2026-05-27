import SwiftUI

struct SettingsView: View {
    @Environment(ContentCoordinator.self) private var coordinator
    @AppStorage("darkMode") private var isDarkMode = false
    @State private var exportError: String?
    @State private var exportData: Data?

    var body: some View {
        NavigationStack {
            List {
                Section("Kernel") {
                    Button(action: { rePatchKernel() }) {
                        Label("Re-patch Kernel", systemImage: "bolt.shield.fill")
                    }
                    Button(action: { Task { await reregisterAll() } }) {
                        Label("Re-register All Apps", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                Section("Data") {
                    if let exportError {
                        Label(exportError, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                    if let exportData {
                        ShareLink(item: exportData, preview: .init("Installed Apps")) {
                            Label("Export App List", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .task {
                    guard exportData == nil else { return }
                    do {
                        exportData = try JSONEncoder().encode(PersistenceService().loadInstalledApps())
                    } catch {
                        exportError = "Export failed: \(error.localizedDescription)"
                    }
                }

                Section("Diagnostics") {
                    NavigationLink(destination: ExploitLogView()) {
                        Label("Exploit Log", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink(destination: AboutView()) {
                        Label("About", systemImage: "info.circle")
                    }
                }

                Section("Debug") {
                    Toggle("Dark Mode", isOn: $isDarkMode)
                }
            }
            .navigationTitle("Settings")
        }
    }

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
        _ = try? await remoteCall.execute(
            inProcess: pid,
            command: "/usr/bin/uicache -r"
        )
        LogManager.shared.append("Re-registration complete", tag: "Settings")
    }

}

struct ExploitLogView: View {
    @Environment(ContentCoordinator.self) private var coordinator

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

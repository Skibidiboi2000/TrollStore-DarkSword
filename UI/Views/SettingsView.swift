import SwiftUI

struct SettingsView: View {
    @Environment(ContentCoordinator.self) private var coordinator
    @AppStorage("darkMode") private var isDarkMode = false

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
                    if let exportData = try? JSONEncoder().encode(
                        PersistenceService().loadInstalledApps()
                    ) {
                        ShareLink(item: exportData, preview: .init("Installed Apps")) {
                            Label("Export App List", systemImage: "square.and.arrow.up")
                        }
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
        guard let handle = coordinator.kernelHandle else {
            print("[Settings] No kernel handle available")
            return
        }
        let kernelBase = XPFWrapper.findKernelBase()
        guard kernelBase > 0 else {
            print("[Settings] Kernel base resolution failed — cannot re-patch")
            return
        }
        let patcher = KernelPatcher(handle: handle, kernelBase: kernelBase)
        if patcher.applyAll() {
            print("[Settings] Kernel re-patched ✓")
        } else {
            print("[Settings] Kernel re-patch failed")
        }
    }

    private func reregisterAll() async {
        guard let handle = coordinator.kernelHandle else {
            print("[Settings] No kernel handle available")
            return
        }
        let remoteCall = RemoteCallEngine(kernelHandle: handle)
        let springBoard = SpringBoardExecutor(remoteCall: remoteCall)
        let persistence = PersistenceService()
        let apps = persistence.loadInstalledApps()
        print("[Settings] Re-registering \(apps.count) apps via uicache -r")
        guard let pid = springBoard.springBoardPID else {
            print("[Settings] SpringBoard not found — cannot re-register")
            return
        }
        _ = try? await remoteCall.execute(
            inProcess: pid,
            command: "/usr/bin/uicache -r"
        )
        print("[Settings] Re-registration complete")
    }

}

struct ExploitLogView: View {
    @Environment(ContentCoordinator.self) private var coordinator

    var body: some View {
        ScrollView {
            if coordinator.exploitLog.isEmpty {
                Text("No exploit log entries yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
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

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var coordinator: ContentCoordinator
    @AppStorage("darkMode") private var isDarkMode = false
    @State private var confirmUninstallAll = false
    @State private var icmp6filtOffsetText: String

    init() {
        let stored = UserDefaults.standard.object(forKey: "lara.offset.off_inpcb_inp_depend6_inp6_icmp6filt") as? UInt32 ?? 0x148
        _icmp6filtOffsetText = State(initialValue: "0x" + String(stored, radix: 16))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    // Kernel
                    AppTheme.sectionHeader("Kernel")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    kernelSection
                        .padding(.horizontal, 20)

                    // General
                    AppTheme.sectionHeader("General")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    generalSection
                        .padding(.horizontal, 20)

                    // Data
                    AppTheme.sectionHeader("Data")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    dataSection
                        .padding(.horizontal, 20)

                    // Offsets
                    AppTheme.sectionHeader("Offsets")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    offsetsSection
                        .padding(.horizontal, 20)

                    // Diagnostics
                    AppTheme.sectionHeader("Diagnostics")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    diagnosticsSection
                        .padding(.horizontal, 20)

                    // Danger Zone
                    AppTheme.sectionHeader("Danger Zone")
                        .foregroundColor(AppTheme.failureColor)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    dangerSection
                        .padding(.horizontal, 20)

                    Color.clear.frame(height: 20)
                }
            }
            .navigationBarHidden(true)
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

    // MARK: - Kernel Section

    private var kernelSection: some View {
        VStack(spacing: 0) {
            SettingsActionRow(icon: "lock.shield.fill", color: AppTheme.accentColor, title: "Re-patch Kernel") {
                rePatchKernel()
            }
            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 52)

            SettingsActionRow(icon: "arrow.triangle.2.circlepath", color: AppTheme.purpleAccent, title: "Re-register All Apps") {
                Task { await reregisterAll() }
            }
            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 52)

            SettingsActionRow(icon: "magnifyingglass.circle.fill", color: AppTheme.accentColor, title: "Rescan Installed Apps") {
                Task { await rescanApps() }
            }
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    // MARK: - General Section

    private var generalSection: some View {
        VStack(spacing: 0) {
            SettingsToggleRow(
                icon: "moon.fill", color: AppTheme.purpleAccent,
                title: "Dark Mode",
                isOn: $isDarkMode
            )
            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 52)

            SettingsToggleRow(
                icon: "arrow.down.to.line", color: AppTheme.orangeAccent,
                title: "Persist Installation",
                isOn: Binding(
                    get: { coordinator.persistInstallation },
                    set: { coordinator.persistInstallation = $0 }
                )
            )
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    // MARK: - Data Section

    private var dataSection: some View {
        VStack(spacing: 0) {
            SettingsActionRow(icon: "square.and.arrow.up.fill", color: AppTheme.successColor, title: "Export App List") {
                exportAppList()
            }
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    // MARK: - Offsets Section

    private var offsetsSection: some View {
        VStack(spacing: 0) {
            DisclosureGroup("Modify Offsets") {
                HStack {
                    Text("icmp6_filter offset")
                    Spacer()
                    TextField("0x148", text: $icmp6filtOffsetText)
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .onSubmit {
                            saveOffsetOverride()
                        }
                }
                .padding(.trailing, 8)
                Text("Restart exploit after changing")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    // MARK: - Diagnostics Section

    private var diagnosticsSection: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: LogDetailView(log: coordinator.exploitLog)) {
                SettingsChevronRow(icon: "list.bullet.rectangle.fill", color: .gray, title: "Exploit Log")
            }
            .buttonStyle(.plain)

            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 52)

            NavigationLink(destination: AboutView()) {
                SettingsChevronRow(icon: "info.circle.fill", color: AppTheme.accentColor, title: "About")
            }
            .buttonStyle(.plain)
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    // MARK: - Danger Zone

    private var dangerSection: some View {
        VStack(spacing: 0) {
            Button(action: { confirmUninstallAll = true }) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(AppTheme.failureColor)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "trash.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        )
                    Text("Uninstall All Apps")
                        .font(.body)
                        .foregroundColor(AppTheme.failureColor)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
            }
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .stroke(AppTheme.failureColor.opacity(0.1), lineWidth: 0.5)
        )
    }

    // MARK: - Actions

    private func saveOffsetOverride() {
        let cleaned = icmp6filtOffsetText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "0x", with: "")
        guard let value = UInt32(cleaned, radix: 16) else {
            LogManager.shared.append("Invalid offset value: \(icmp6filtOffsetText)", tag: "Settings")
            return
        }
        UserDefaults.standard.set(value, forKey: "lara.offset.off_inpcb_inp_depend6_inp6_icmp6filt")
        LogManager.shared.append("icmp6_filter offset set to 0x\(String(value, radix: 16))", tag: "Settings")
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
        _ = try? await remoteCall.execute(inProcess: pid, command: "/usr/bin/uicache -r")
        LogManager.shared.append("Re-registration complete", tag: "Settings")
    }

    private func rescanApps() async {
        let count = PersistenceService().rescanApplicationsDirectory().count
        LogManager.shared.append("Rescanned /Applications/ — \(count) apps tracked", tag: "Settings")
    }

    private func exportAppList() {
        do {
            let data = try JSONEncoder().encode(PersistenceService().loadInstalledApps())
            LogManager.shared.append("Exported \(data.count) bytes", tag: "Settings")
        } catch {
            LogManager.shared.append("Export failed: \(error.localizedDescription)", tag: "Settings")
        }
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

// MARK: - Reusable Settings Row Components

private struct SettingsActionRow: View {
    let icon: String
    let color: Color
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(color)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    )
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let color: Color
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7)
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                )
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppTheme.successColor)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }
}

private struct SettingsChevronRow: View {
    let icon: String
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7)
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                )
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.labelTertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }
}

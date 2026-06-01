import SwiftUI
import UniformTypeIdentifiers

struct InstallView: View {
    @EnvironmentObject private var coordinator: ContentCoordinator
    @State private var installer: IPAInstaller?
    @State private var showFilePicker = false
    @State private var filePickerError: String?
    @State private var installStatus: InstallStatus = .idle
    @State private var installProgress: Double = 0.0
    @State private var installError: String?
    @State private var persistence = PersistenceService()

    /// Tracks whether a `DocumentPickerView` is actively presenting.
    /// Used instead of `.fileImporter` which has a known callback-breaking bug when
    /// nested inside a `TabView` on iOS 17+.
    @State private var isDocumentPickerPresented = false

    enum InstallStatus: Equatable {
        case idle
        case importing(String)
        case parsing
        case injectingEntitlements
        case copyingToApplications
        case registeringWithLaunchServices
        case complete
        case failed(String)
    }

    private var isInstallerReady: Bool { installer != nil }

    var body: some View {
        NavigationStack {
            if coordinator.kernelHandle == nil {
                notReadyView
            } else if installStatus == .idle {
                idleView
            } else {
                progressView
            }
        }
        // A UIViewControllerRepresentable wrapper used INSTEAD of .fileImporter to
        // avoid the iOS 17+ TabView callback bug.  Using asCopy: true so the file is
        // an app-owned copy with no security-scoping needed.
        .overlay(
            DocumentPickerView(
                isPresented: $isDocumentPickerPresented,
                onPick: { url in handleFilePickerSelection(url) }
            )
            .allowsHitTesting(false)
            .frame(width: 0, height: 0)
        )
        .onChange(of: showFilePicker) { newValue in
            if newValue {
                isDocumentPickerPresented = true
                showFilePicker = false
            }
        }
        .onChange(of: coordinator.pendingIPAURL) { url in
            guard let url else { return }
            Task { await startInstall(url: url); coordinator.pendingIPAURL = nil }
        }
        .onChange(of: coordinator.kernelHandle) { newHandle in
            guard let newHandle, installer == nil else { return }
            buildInstaller(handle: newHandle)
        }
        .onChange(of: coordinator.importError) { error in
            guard let error else { return }
            installError = error
            installStatus = .failed(error)
        }
        .onAppear {
            if let handle = coordinator.kernelHandle, installer == nil {
                buildInstaller(handle: handle)
            }
        }
    }

    // MARK: - Not Ready

    private var notReadyView: some View {
        ContentUnavailableView(
            "No Kernel Access",
            systemImage: "lock.shield.fill",
            description: Text("Run the exploit first to enable installation.")
        )
        .navigationTitle("Install")
    }

    // MARK: - Idle View

    private var idleView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 40)

                RoundedRectangle(cornerRadius: 22)
                    .fill(AppTheme.accentGradient)
                    .frame(width: 80, height: 80)
                    .shadow(color: .blue.opacity(0.3), radius: 16, y: 8)
                    .overlay(
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 36))
                            .foregroundColor(.white)
                    )

                VStack(spacing: 6) {
                    Text("Install IPA")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Import an IPA file to install it\nwith full entitlements.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }

                Button(action: { showFilePicker = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.badge.plus")
                        Text("Select IPA File")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: 280)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                if let error = filePickerError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .font(.caption)
                }

                recentInstallsSection
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .navigationTitle("Install")
        .scrollIndicators(.hidden)
    }

    // MARK: - Recently Installed

    private var recentInstallsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recently Installed")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            let recent = persistence.loadInstalledApps()
                .sorted { $0.installDate > $1.installDate }
                .prefix(3)

            if recent.isEmpty {
                HStack {
                    Text("No recent installs")
                        .font(.subheadline)
                        .foregroundColor(Color(.tertiaryLabel))
                    Spacer()
                }
                .padding(16)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.offset) { _, app in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(recentIconGradient(for: app))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "app.fill")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                )

                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(app.installDate, style: .relative)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        if app.bundleID != recent.last?.bundleID {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.top, 16)
    }

    private func recentIconGradient(for app: InstalledApp) -> LinearGradient {
        let gradients = [
            LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing),
        ]
        return gradients[abs(app.bundleID.hashValue) % gradients.count]
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 4)
                        .frame(width: 72, height: 72)

                    Circle()
                        .trim(from: 0, to: installProgress)
                        .stroke(AppTheme.successGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut, value: installProgress)

                    if installStatus == .complete {
                        Image(systemName: "checkmark")
                            .font(.title.bold())
                            .foregroundColor(.green)
                    }
                }

                Text(installStatusLabel)
                    .font(.headline)
            }

            // Step indicators
            VStack(spacing: 0) {
                installStepRow(label: "Importing", stage: .importing("Importing IPA..."))
                Divider()
                installStepRow(label: "Parsing", stage: .parsing)
                Divider()
                installStepRow(label: "Injecting entitlements", stage: .injectingEntitlements)
                Divider()
                installStepRow(label: "Copying to /Applications/", stage: .copyingToApplications)
                Divider()
                installStepRow(label: "Registering with LaunchServices", stage: .registeringWithLaunchServices)
            }
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 32)

            if installStatus == .complete {
                Button("Dismiss") {
                    installStatus = .idle
                    installProgress = 0.0
                }
                .buttonStyle(.bordered)
            } else if case .failed(let reason) = installStatus {
                VStack(spacing: 8) {
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Button("Try Again") {
                            installStatus = .idle
                            installProgress = 0.0
                            installError = nil
                        }
                        .buttonStyle(.bordered)

                        if let logURL = LogManager.shared.currentLogURL {
                            ShareLink(item: logURL) {
                                Label("Share Log", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Spacer()
        }
        .navigationTitle("Installing")
    }

    private func installStepRow(label: String, stage: InstallStatus) -> some View {
        HStack(spacing: 10) {
            ZStack {
                if isStageDone(stage) {
                    Circle()
                        .fill(.green)
                        .frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else if isStageActive(stage) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 22, height: 22)
                        .shadow(color: .blue.opacity(0.3), radius: 4)
                    Circle()
                        .fill(.white)
                        .frame(width: 6, height: 6)
                } else {
                    Circle()
                        .fill(Color(.systemGray4))
                        .frame(width: 22, height: 22)
                }
            }

            Text(label)
                .font(.subheadline)
                .foregroundColor(isStageDone(stage) ? .secondary : .primary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isStageActive(stage) ? Color.blue.opacity(0.05) : Color.clear)
    }

    private var installStatusLabel: String {
        switch installStatus {
        case .idle: return ""
        case .importing: return "Importing IPA..."
        case .parsing: return "Parsing..."
        case .injectingEntitlements: return "Injecting entitlements..."
        case .copyingToApplications: return "Copying..."
        case .registeringWithLaunchServices: return "Registering..."
        case .complete: return "Install complete!"
        case .failed: return "Install failed"
        }
    }

    private static func stageOrder(_ stage: InstallStatus) -> Int {
        switch stage {
        case .idle: return -1
        case .importing: return 0
        case .parsing: return 1
        case .injectingEntitlements: return 2
        case .copyingToApplications: return 3
        case .registeringWithLaunchServices: return 4
        case .complete: return 5
        case .failed: return -1
        }
    }

    private var currentStageIndex: Int { Self.stageOrder(installStatus) }

    private func isStageDone(_ stage: InstallStatus) -> Bool {
        Self.stageOrder(stage) < currentStageIndex || installStatus == .complete
    }

    private func isStageActive(_ stage: InstallStatus) -> Bool {
        Self.stageOrder(stage) == currentStageIndex
    }

    // MARK: - Logic

    private func buildInstaller(handle: KernelRwHandle) {
        let persistence = PersistenceService()
        let parser = IPAParser()
        let editor = CodeSignatureEditor()
        let remoteCall = RemoteCallEngine(kernelHandle: handle)
        let springBoard = SpringBoardExecutor(remoteCall: remoteCall)
        installer = IPAInstaller(
            parser: parser,
            signatureEditor: editor,
            springBoard: springBoard,
            persistence: persistence,
            shouldPersist: coordinator.persistInstallation
        )
    }

    /// Called when the `DocumentPickerView` successfully returns a URL.
    /// Because we use `asCopy: true`, the URL points to an app-owned temp file — no
    /// security-scoped resource access is needed.
    private func handleFilePickerSelection(_ url: URL) {
        guard url.pathExtension.lowercased() == "ipa" else {
            filePickerError = "Selected file is not an IPA. Please choose a .ipa file."
            // Delete the stale copy the system created for us.
            try? FileManager.default.removeItem(at: url)
            return
        }
        filePickerError = nil
        Task {
            await startInstall(url: url)
            // The file returned with asCopy: true is a temp copy the system manages.
            // We don't need to stopAccessingSecurityScopedResource because there's
            // no security-scope to manage.
        }
    }

    @MainActor
    private func startInstall(url: URL) async {
        guard let installer else {
            filePickerError = "Installer not ready — kernel exploit may still be running."
            return
        }

        installStatus = .importing("Importing IPA...")
        installProgress = 0.1
        installError = nil

        do {
            for try await stage in installer.install(ipaURL: url) {
                switch stage {
                case .parsing:
                    installStatus = .parsing; installProgress = 0.25
                case .injectingEntitlements:
                    installStatus = .injectingEntitlements; installProgress = 0.5
                case .copyingToApplications:
                    installStatus = .copyingToApplications; installProgress = 0.75
                case .registeringWithLaunchServices:
                    installStatus = .registeringWithLaunchServices; installProgress = 0.9
                case .complete:
                    installStatus = .complete; installProgress = 1.0
                }
            }
        } catch {
            LogManager.shared.append(
                "[\(type(of: error))] \(error.localizedDescription)",
                tag: "InstallView"
            )
            installStatus = .failed(error.localizedDescription)
            installProgress = 0.0
        }
    }
}



import SwiftUI
import UniformTypeIdentifiers

struct InstallView: View {
    @EnvironmentObject private var coordinator: ContentCoordinator
    @State private var installer: IPAInstaller?
    @State private var showFilePicker = false
    @State private var filePickerError: String?
    @State private var installStatus: InstallStatus = .idle
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
            Group {
                if coordinator.kernelHandle == nil {
                    notReadyView
                } else if installStatus == .idle {
                    idleView
                } else {
                    progressView
                }
            }
        }
        .overlay(
            DocumentPickerView(
                isPresented: $isDocumentPickerPresented,
                onPick: { url in handleFilePickerSelection(url) }
            )
            .allowsHitTesting(false)
            .frame(width: 0, height: 0)
        )
        .onChange(of: showFilePicker) { _ in
            if showFilePicker {
                isDocumentPickerPresented = true
                showFilePicker = false
            }
        }
        .onChange(of: coordinator.pendingIPAURL) { _ in
            guard let url = coordinator.pendingIPAURL else { return }
            Task { await startInstall(url: url); coordinator.pendingIPAURL = nil }
        }
        .onChange(of: coordinator.kernelHandle) { _ in
            guard let handle = coordinator.kernelHandle, installer == nil else { return }
            buildInstaller(handle: handle)
        }
        .onChange(of: coordinator.importError) { _ in
            guard let error = coordinator.importError else { return }
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
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36))
                .foregroundColor(AppTheme.labelTertiary)
            Text("No Kernel Access")
                .font(.headline)
                .foregroundColor(AppTheme.labelSecondary)
            Text("Run the exploit first to enable installation.")
                .font(.body)
                .foregroundColor(AppTheme.labelTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Idle View

    private var idleView: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Install")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                // IPA Import Button
                Button(action: { showFilePicker = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.badge.plus")
                            .font(.body)
                        Text("Select IPA File")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 12)

                if let error = filePickerError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                    }
                    .foregroundColor(AppTheme.failureColor)
                    .padding(.top, 8)
                }

                // Recent Installs
                AppTheme.sectionHeader("Recently Installed")
                    .frame(maxWidth: .infinity, alignment: .leading)

                recentInstallsSection
                    .padding(.horizontal, 20)

                Color.clear.frame(height: 20)
            }
        }
    }

    // MARK: - Recently Installed

    private var recentInstallsSection: some View {
        let recent = persistence.loadInstalledApps()
            .sorted { $0.installDate > $1.installDate }
            .prefix(3)

        return Group {
            if recent.isEmpty {
                HStack {
                    Text("No recent installs")
                        .font(.body)
                        .foregroundColor(AppTheme.labelTertiary)
                    Spacer()
                }
                .padding(16)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.offset) { _, app in
                        recentRow(app: app)
                        if app.bundleID != recent.last?.bundleID {
                            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 68)
                        }
                    }
                }
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
            }
        }
    }

    private func recentRow(app: InstalledApp) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(recentIconGradient(for: app))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "app.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)
                    .fontWeight(.medium)
                Text(app.installDate, style: .relative)
                    .font(.caption)
                    .foregroundColor(AppTheme.labelTertiary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppTheme.successColor)
                .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func recentIconGradient(for app: InstalledApp) -> LinearGradient {
        let gradients = [
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
        ]
        return gradients[abs(app.bundleID.hashValue) % gradients.count]
    }

    // MARK: - Progress View

    private var progressView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Ring + Label
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(AppTheme.labelTertiary.opacity(0.24), lineWidth: 3.5)
                            .frame(width: 60, height: 60)

                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(AppTheme.accentColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(-90))

                        if installStatus == .complete {
                            Image(systemName: "checkmark")
                                .font(.title.bold())
                                .foregroundColor(AppTheme.successColor)
                        }
                    }

                    Text(installStatusLabel)
                        .font(.headline)
                }
                .padding(.vertical, 16)

                // Steps
                AppTheme.sectionHeader("Steps")
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 0) {
                    installStepRow(label: "Importing", stage: .importing(""))
                    AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 46)
                    installStepRow(label: "Parsing", stage: .parsing)
                    AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 46)
                    installStepRow(label: "Injecting entitlements", stage: .injectingEntitlements)
                    AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 46)
                    installStepRow(label: "Copying to /Applications/", stage: .copyingToApplications)
                    AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 46)
                    installStepRow(label: "Registering with LaunchServices", stage: .registeringWithLaunchServices)
                }
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
                .padding(.horizontal, 20)

                // Dismiss / Retry
                if installStatus == .complete {
                    Button("Dismiss") {
                        installStatus = .idle
                    }
                    .buttonStyle(.plain)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: 200)
                    .padding(.vertical, 12)
                    .background(AppTheme.cardBackground)
                    .foregroundColor(AppTheme.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 20)
                } else if case .failed(let reason) = installStatus {
                    VStack(spacing: 12) {
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 12) {
                            Button("Try Again") {
                                installStatus = .idle
                                installError = nil
                            }
                            .buttonStyle(.plain)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(AppTheme.cardBackground)
                            .foregroundColor(AppTheme.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                            if let logURL = LogManager.shared.currentLogURL {
                                ShareLink(item: logURL) {
                                    Label("Share Log", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.plain)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(AppTheme.cardBackground)
                                .foregroundColor(AppTheme.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .padding(.top, 20)
                }

                Color.clear.frame(height: 20)
            }
        }
    }

    private func installStepRow(label: String, stage: InstallStatus) -> some View {
        HStack(spacing: 10) {
            ZStack {
                if isStageDone(stage) {
                    Circle()
                        .fill(AppTheme.successColor)
                        .frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else if isStageActive(stage) {
                    Circle()
                        .fill(AppTheme.accentColor)
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                } else {
                    Circle()
                        .fill(AppTheme.labelTertiary.opacity(0.16))
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(AppTheme.labelTertiary.opacity(0.6))
                        .frame(width: 7, height: 7)
                }
            }

            Text(label)
                .font(.body)
                .foregroundColor(isStageDone(stage) ? .secondary : .primary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isStageActive(stage) ? AppTheme.accentColor.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private func handleFilePickerSelection(_ url: URL) {
        guard url.pathExtension.lowercased() == "ipa" else {
            filePickerError = "Selected file is not an IPA. Please choose a .ipa file."
            try? FileManager.default.removeItem(at: url)
            return
        }
        filePickerError = nil
        Task {
            await startInstall(url: url)
        }
    }

    @MainActor
    private func startInstall(url: URL) async {
        guard let installer else {
            filePickerError = "Installer not ready — kernel exploit may still be running."
            try? FileManager.default.removeItem(at: url)
            return
        }

        installStatus = .importing("Importing IPA...")
        installError = nil

        do {
            for try await stage in installer.install(ipaURL: url) {
                switch stage {
                case .parsing:
                    installStatus = .parsing
                case .injectingEntitlements:
                    installStatus = .injectingEntitlements
                case .copyingToApplications:
                    installStatus = .copyingToApplications
                case .registeringWithLaunchServices:
                    installStatus = .registeringWithLaunchServices
                case .complete:
                    installStatus = .complete
                    coordinator.appendActivity(ActivityEntry(message: "IPA installed successfully", type: .success))
                }
            }
        } catch {
            LogManager.shared.append(
                "[\(type(of: error))] \(error.localizedDescription)",
                tag: "InstallView"
            )
            installStatus = .failed(error.localizedDescription)
            coordinator.appendActivity(ActivityEntry(message: "Install failed: \(error.localizedDescription)", type: .error))
        }
        // Clean up the temp IPA copy from the document picker
        try? FileManager.default.removeItem(at: url)
    }
}

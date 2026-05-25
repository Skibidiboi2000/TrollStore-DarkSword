import SwiftUI
import UniformTypeIdentifiers

struct InstallView: View {
    @Environment(ContentCoordinator.self) private var coordinator
    @State private var viewModel: InstallViewModel?
    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            if coordinator.kernelHandle == nil {
                ContentUnavailableView(
                    "No Kernel Access",
                    systemImage: "lock.shield.fill",
                    description: Text("Run the exploit first to enable installation.")
                )
            } else if let viewModel, viewModel.status != .idle {
                VStack(spacing: 24) {
                    Spacer()
                    installProgressView(viewModel.status)
                    Spacer()
                }
                .navigationTitle("Install")
            } else {
                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "plus.app.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.accentColor)

                    Text("Install IPA")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Import an IPA file to install it\nwith full entitlements.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)

                    Button(action: { showFilePicker = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.badge.plus")
                            Text("Select IPA File")
                        }
                        .frame(maxWidth: 280)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }
                .navigationTitle("Install")
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await viewModel?.installIPA(at: url) }
            case .failure(let error):
                viewModel?.status = .failed(error.localizedDescription)
            }
        }
        .onAppear {
            guard viewModel == nil else { return }
            guard let handle = coordinator.kernelHandle else {
                print("[InstallView] Deferred: no kernel handle yet")
                return
            }
            let persistence = PersistenceService()
            let parser = IPAParser()
            let editor = CodeSignatureEditor()
            let remoteCall = RemoteCallEngine(kernelHandle: handle)
            let springBoard = SpringBoardExecutor(remoteCall: remoteCall)
            let installer = IPAInstaller(
                parser: parser,
                signatureEditor: editor,
                springBoard: springBoard,
                persistence: persistence
            )
            viewModel = InstallViewModel(installer: installer)
        }
    }

    @ViewBuilder
    private func installProgressView(_ status: InstallViewModel.InstallStatus) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: viewModel?.progress ?? 0.5, total: 1.0)
                .progressViewStyle(.linear)
                .frame(maxWidth: 280)

            switch status {
            case .importing(let detail):
                Label(detail, systemImage: "doc.text.magnifyingglass")
            case .parsing:
                Label("Parsing IPA...", systemImage: "doc.text")
            case .injectingEntitlements:
                Label("Injecting entitlements...", systemImage: "key.fill")
            case .copyingToApplications:
                Label("Copying to /Applications/...", systemImage: "folder.fill")
            case .registeringWithLaunchServices:
                Label("Registering with LaunchServices...", systemImage: "arrow.triangle.branch")
            case .complete:
                Label("Install complete!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed(let reason):
                VStack(spacing: 8) {
                    Label("Failed", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        viewModel?.status = .idle
                    }
                }
            case .idle:
                EmptyView()
            }
        }
    }
}

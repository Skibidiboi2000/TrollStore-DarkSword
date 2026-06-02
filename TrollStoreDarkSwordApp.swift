import SwiftUI

@main
struct TrollStoreDarkSwordApp: App {
    @State private var coordinator = ContentCoordinator()
    @AppStorage("darkMode") private var isDarkMode = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .preferredColorScheme(isDarkMode ? .dark : nil)
                .onOpenURL { url in
                    coordinator.handleImportedIPA(url)
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var coordinator: ContentCoordinator

    private var viewModel: ExploitViewModel {
        coordinator.exploitViewModel
    }

    var body: some View {
        ZStack {
            switch coordinator.appState {
            case .sandboxed:
                ExploitView()
                    .transition(.opacity)

            case .obtainingOffsets, .exploiting:
                ExploitProgressView()
                    .transition(.opacity)

            case .exploitFailed(let reason):
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(AppTheme.failureColor)
                        Text(coordinator.deviceInfo.isSupported ? "Exploit Failed" : "Unsupported Device")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(reason)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        if coordinator.deviceInfo.isSupported {
                            Button("Try Again") {
                                coordinator.appState = .sandboxed
                            }
                            .buttonStyle(.plain)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(AppTheme.cardBackground)
                            .foregroundColor(AppTheme.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(24)
                }
                .transition(.opacity)

            case .patched:
                if viewModel.currentStage == .complete && !coordinator.hasSeenSuccess {
                    ExploitSuccessView()
                        .transition(.opacity)
                } else {
                    PatchedView()
                        .transition(.opacity)
                }

            case .panicRecovery:
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(AppTheme.orangeAccent)
                        Text("Panic Detected")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("The device may have panicked. If it rebooted, re-launch the app.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("OK") {
                            coordinator.acknowledgePanic()
                        }
                        .buttonStyle(.plain)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(AppTheme.orangeAccent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(24)
                }
                .transition(.opacity)
            }
        }
        .animation(.default, value: coordinator.appState)
    }
}

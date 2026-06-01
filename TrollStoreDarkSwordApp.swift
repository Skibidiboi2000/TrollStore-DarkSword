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
        Group {
            switch coordinator.appState {
            case .sandboxed:
                ExploitView()
                    .transition(AppTheme.springTransition)

            case .obtainingOffsets, .exploiting:
                ExploitProgressView()
                    .transition(AppTheme.springTransition)

            case .exploitFailed(let reason):
                VStack(spacing: 16) {
                    Text(coordinator.deviceInfo.isSupported ? "Exploit Failed" : "Unsupported Device")
                        .font(.title)
                        .foregroundColor(.red)
                    Text(reason)
                        .font(.body)
                        .multilineTextAlignment(.center)
                    if coordinator.deviceInfo.isSupported {
                        Button("Retry") {
                            coordinator.appState = .sandboxed
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .transition(AppTheme.springTransition)

            case .patched:
                if viewModel.currentStage == .complete && !coordinator.hasSeenSuccess {
                    ExploitSuccessView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity.combined(with: .move(edge: .bottom))
                        ))
                } else {
                    PatchedView()
                        .transition(.opacity)
                }

            case .panicRecovery:
                VStack(spacing: 16) {
                    Text("Panic Detected")
                        .font(.title)
                    Text("The device may have panicked. If it rebooted, re-launch the app.")
                    Button("OK") {
                        coordinator.acknowledgePanic()
                    }
                }
                .padding()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: coordinator.appState)
    }
}

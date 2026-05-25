import SwiftUI

@main
struct TrollStoreDarkSwordApp: App {
    @State private var coordinator = ContentCoordinator()
    @AppStorage("darkMode") private var isDarkMode = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
                .preferredColorScheme(isDarkMode ? .dark : nil)
        }
    }
}

struct ContentView: View {
    @Environment(ContentCoordinator.self) private var coordinator

    var body: some View {
        Group {
            switch coordinator.appState {
            case .sandboxed:
                ExploitView()
            case .obtainingOffsets:
                ExploitProgressView()
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
            case .patched:
                PatchedView()
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
            case .exploiting:
                ExploitProgressView()
            }
        }
        .transition(.opacity.combined(with: .scale))
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: coordinator.appState)
    }
}

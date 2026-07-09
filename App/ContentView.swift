import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var coordinator: ContentCoordinator

    var body: some View {
        ZStack {
            switch coordinator.state {
            case .idle:
                VStack(spacing: 20) {
                    Text("TrollStore DarkSword")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Button("Select IPA") {
                        coordinator.startPipeline()
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .exploiting:
                ProgressView("Running exploit...")
            case .extractingCDHash:
                ProgressView("Extracting CDHash...")
            case .injectingTrustCache:
                ProgressView("Injecting trust cache...")
            case .installing:
                ProgressView("Installing...")
            case .refreshingUI:
                ProgressView("Refreshing UI...")
            case .success:
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.green)
                    Text("App installed successfully!")
                        .font(.title2)
                }
            case .error(let reason):
                VStack(spacing: 16) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text(reason)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        coordinator.state = .idle
                    }
                }
                .padding(24)
            }
        }
    }
}

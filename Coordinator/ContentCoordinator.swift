import Foundation
import SwiftUI

@MainActor
class ContentCoordinator: ObservableObject {
    @Published var state: AppState = .idle
    @Published var log: String = ""

    func startPipeline() {
        // Simplified without IPA path for blueprint matching
        Task {
            do {
                // Phase 1: Exploit
                updateState(.exploiting)
                try DarkSwordExploit.run()
                try SandboxEscape.clear()
                KernelPatcher.setPlatformBinary()

                // Phase 2: Install
                updateState(.installing)
                // IPA install happens here when IPA path provided
                // try IPAInstaller.install(ipaPath: ipaPath)

                // Phase 3: UI Refresh
                updateState(.refreshingUI)
                try await SpringBoardExecutor.refreshIcons()

                updateState(.success)
            } catch {
                updateState(.error(error.localizedDescription))
            }
        }
    }

    private func updateState(_ newState: AppState) {
        state = newState
    }
}

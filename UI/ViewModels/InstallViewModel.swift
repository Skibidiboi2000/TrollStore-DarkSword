import SwiftUI

@MainActor
@Observable
public final class InstallViewModel {
    public enum InstallStatus: Equatable {
        case idle
        case importing(String)
        case parsing
        case injectingEntitlements
        case copyingToApplications
        case registeringWithLaunchServices
        case complete
        case failed(String)
    }

    public var status: InstallStatus = .idle
    public var progress: Double = 0.0

    private let installer: IPAInstaller

    public init(installer: IPAInstaller) {
        self.installer = installer
    }

    public func installIPA(at url: URL) async {
        status = .importing("Parsing IPA...")
        progress = 0.1

        do {
            for try await stage in installer.install(ipaURL: url) {
                switch stage {
                case .parsing:
                    status = .parsing
                    progress = 0.25
                case .injectingEntitlements:
                    status = .injectingEntitlements
                    progress = 0.5
                case .copyingToApplications:
                    status = .copyingToApplications
                    progress = 0.75
                case .registeringWithLaunchServices:
                    status = .registeringWithLaunchServices
                    progress = 0.9
                case .complete:
                    status = .complete
                    progress = 1.0
                }
            }

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            status = .idle
            progress = 0.0

        } catch {
            status = .failed(error.localizedDescription)
            progress = 0.0
        }
    }
}

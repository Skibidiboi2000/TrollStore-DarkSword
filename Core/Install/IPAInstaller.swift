import Foundation

public final class IPAInstaller: @unchecked Sendable {
    public enum InstallStage {
        case parsing
        case injectingEntitlements
        case copyingToApplications
        case registeringWithLaunchServices
        case complete(InstalledApp)
    }

    public enum InstallError: LocalizedError {
        case parserError(IPAParser.ParseError)
        case signatureError(CodeSignatureEditor.EditorError)
        case springBoardError(RemoteCallEngine.RemoteCallError)
        case invalidBinary

        public var errorDescription: String? {
            switch self {
            case .parserError(let e): return e.localizedDescription
            case .signatureError(let e): return e.localizedDescription
            case .springBoardError(let e): return e.localizedDescription
            case .invalidBinary: return "Invalid Mach-O binary."
            }
        }
    }

    private let parser: IPAParser
    private let signatureEditor: CodeSignatureEditor
    private let springBoard: SpringBoardExecutor
    private let persistence: PersistenceService
    private let shouldPersist: Bool
    /// Tracks the current pipeline stage for error logging.
    private var currentStage: String = "idle"

    public init(
        parser: IPAParser,
        signatureEditor: CodeSignatureEditor,
        springBoard: SpringBoardExecutor,
        persistence: PersistenceService,
        shouldPersist: Bool = true
    ) {
        self.parser = parser
        self.signatureEditor = signatureEditor
        self.springBoard = springBoard
        self.persistence = persistence
        self.shouldPersist = shouldPersist
    }

    /// Full installation pipeline as an async stream.
    /// Yields real progress stages as each step completes.
    ///
    /// Pipeline:
    /// 1. Parse the IPA (extract metadata, find binaries)
    /// 2. Inject full entitlements into the main Mach-O
    /// 3. Copy the .app bundle to /Applications/ via SpringBoard
    /// 4. Register with LaunchServices via uicache
    /// 5. Save to persistent installed apps list
    ///
    /// - Parameter ipaURL: URL of the .ipa file to install
    /// - Returns: Async stream emitting real progress stages
    public func install(ipaURL: URL) -> AsyncThrowingStream<InstallStage, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.parsing)
                    currentStage = "parsing"
                    let parsed = try parser.parse(ipaURL: ipaURL)
                    defer { try? FileManager.default.removeItem(atPath: parsed.tempDirectory) }

                    guard FileManager.default.fileExists(atPath: parsed.executablePath) else {
                        throw InstallError.invalidBinary
                    }

                    continuation.yield(.injectingEntitlements)
                    currentStage = "injectingEntitlements"
                    try signatureEditor.injectEntitlements(into: parsed.executablePath)

                    continuation.yield(.copyingToApplications)
                    currentStage = "copyingToApplications"
                    try await springBoard.installAppBundle(
                        sourcePath: parsed.bundlePath,
                        bundleID: parsed.bundleID
                    )

                    continuation.yield(.registeringWithLaunchServices)
                    currentStage = "registeringWithLaunchServices"
                    try await springBoard.registerApp(bundleID: parsed.bundleID)

                    let app = InstalledApp(
                        name: parsed.name,
                        bundleID: parsed.bundleID,
                        version: parsed.version,
                        path: "/Applications/\(parsed.bundleID).app",
                        iconPath: parsed.iconPaths.first,
                        executableName: parsed.executableName
                    )

                    if shouldPersist {
                        persistence.addApp(app)
                    }

                    LogManager.shared.append("Installed \(parsed.name) v\(parsed.version)", tag: "IPAInstaller")
                    continuation.yield(.complete(app))
                    continuation.finish()
                } catch {
                    LogManager.shared.append(
                        "[\(currentStage)] \(type(of: error)): \(error.localizedDescription)",
                        tag: "InstallFatal"
                    )
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Full uninstallation pipeline:
    /// 1. Remove from /Applications/ via SpringBoard
    /// 2. De-register from LaunchServices
    /// 3. Remove from persistent storage
    ///
    /// - Parameter bundleID: Bundle identifier to uninstall
    public func uninstall(bundleID: String) async throws {
        try await springBoard.uninstallAppBundle(bundleID: bundleID)
        persistence.removeApp(bundleID: bundleID)
        LogManager.shared.append("Uninstalled \(bundleID)", tag: "IPAInstaller")
    }
}

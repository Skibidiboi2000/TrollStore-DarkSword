import Foundation

/// Specialized RemoteCall wrapper for SpringBoard operations.
///
/// SpringBoard runs as the mobile user and is not sandboxed,
/// making it the ideal process to copy files to /Applications/,
/// run uicache for LaunchServices registration, and launch apps.
@MainActor
public final class SpringBoardExecutor {
    private let remoteCall: RemoteCallEngine

    public init(remoteCall: RemoteCallEngine) {
        self.remoteCall = remoteCall
    }

    /// Find SpringBoard's process ID.
    public var springBoardPID: pid_t? {
        return remoteCall.findProcess(named: "SpringBoard")
    }

    /// Open a SpringBoard RemoteCall connection.
    private func connect() throws -> RemoteCall {
        guard let _ = springBoardPID else {
            throw RemoteCallEngine.RemoteCallError.targetNotFound("SpringBoard (pid: 0)")
        }
        return try remoteCall.connectToProcess(named: "SpringBoard")
    }

    /// Validate a bundle ID contains only safe characters (alphanumeric, dots, hyphens).
    private static func isValidBundleID(_ id: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        return !id.isEmpty && id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Escape a path for safe use in a shell command string.
    /// Single quotes are terminated and escaped, then the string is re-quoted.
    private static func shellEscape(_ string: String) -> String {
        "'\(string.replacingOccurrences(of: "'", with: "'\''"))'"
    }

    /// Copy an app bundle to /Applications/ using SpringBoard's privileges.
    @discardableResult
    public func installAppBundle(sourcePath: String, bundleID: String) async throws -> Bool {
        guard Self.isValidBundleID(bundleID) else {
            throw RemoteCallEngine.RemoteCallError.executionFailed("Invalid bundle ID: \(bundleID)")
        }
        guard let pid = springBoardPID else {
            throw RemoteCallEngine.RemoteCallError.targetNotFound("SpringBoard (pid: 0)")
        }

        let destPath = "/Applications/\(bundleID).app"
        let command = "cp -R \(Self.shellEscape(sourcePath)) \(Self.shellEscape(destPath)) && chmod -R 755 \(Self.shellEscape(destPath))"

        _ = try await remoteCall.execute(inProcess: pid, command: command)
        print("[SpringBoardExecutor] Bundle copied to \(destPath)")
        return true
    }

    /// Run uicache to register the app with LaunchServices.
    @discardableResult
    public func registerApp(bundleID: String) async throws -> Bool {
        guard Self.isValidBundleID(bundleID) else {
            throw RemoteCallEngine.RemoteCallError.executionFailed("Invalid bundle ID: \(bundleID)")
        }
        guard let pid = springBoardPID else {
            throw RemoteCallEngine.RemoteCallError.targetNotFound("SpringBoard (pid: 0)")
        }

        let command = "/usr/bin/uicache -r -b \(Self.shellEscape(bundleID))"
        _ = try await remoteCall.execute(inProcess: pid, command: command)
        print("[SpringBoardExecutor] uicache registered \(bundleID)")
        return true
    }

    /// Remove an app bundle from /Applications/ and de-register.
    @discardableResult
    public func uninstallAppBundle(bundleID: String) async throws -> Bool {
        guard Self.isValidBundleID(bundleID) else {
            throw RemoteCallEngine.RemoteCallError.executionFailed("Invalid bundle ID: \(bundleID)")
        }
        guard let pid = springBoardPID else {
            throw RemoteCallEngine.RemoteCallError.targetNotFound("SpringBoard (pid: 0)")
        }

        let path = "/Applications/\(bundleID).app"
        let command = "rm -rf \(Self.shellEscape(path)) && /usr/bin/uicache -r -b \(Self.shellEscape(bundleID))"
        _ = try await remoteCall.execute(inProcess: pid, command: command)
        print("[SpringBoardExecutor] Removed \(path)")
        return true
    }

    /// Launch an installed app via LSApplicationWorkspace in SpringBoard.
    /// Uses the same RemoteCall / Mach exception hijack path as install/uninstall.
    public func launchApp(bundleID: String) async throws {
        guard Self.isValidBundleID(bundleID) else {
            throw RemoteCallEngine.RemoteCallError.executionFailed("Invalid bundle ID: \(bundleID)")
        }
        let rc = try connect()

        let lsCls = remote_getClass(rc, "LSApplicationWorkspace")
        guard lsCls > 0 else {
            throw RemoteCallEngine.RemoteCallError.executionFailed("remote_getClass LSApplicationWorkspace")
        }

        let sel = remote_sel(rc, "defaultWorkspace")
        let workspace = remote_msg(rc, lsCls, sel, 0, 0, 0, 0)
        guard workspace > 0 else {
            throw RemoteCallEngine.RemoteCallError.executionFailed("defaultWorkspace")
        }

        let bundleStr = remote_NSString(rc, bundleID)
        guard bundleStr > 0 else {
            throw RemoteCallEngine.RemoteCallError.executionFailed("remote_NSString bundleID")
        }

        let openSel = remote_sel(rc, "openApplicationWithBundleID:")
        guard openSel > 0 else {
            throw RemoteCallEngine.RemoteCallError.executionFailed("remote_sel openApplicationWithBundleID:")
        }

        let result = remote_msg(rc, workspace, openSel, bundleStr, 0, 0, 0)
        guard result > 0 else {
            throw RemoteCallEngine.RemoteCallError.executionFailed("openApplicationWithBundleID:")
        }

        print("[SpringBoardExecutor] Launched \(bundleID)")
    }
}

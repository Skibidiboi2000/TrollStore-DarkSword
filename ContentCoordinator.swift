import SwiftUI

@MainActor
@Observable
public final class ContentCoordinator {
    /// Shared UserDefaults key used for kernel-panic detection across app launches.
    public static let panicFlagKey = "com.trollstoredarksword.exploitRunning"
    public let deviceInfo = DeviceInfo.current
    public var appState: AppState = .sandboxed
    public var exploitLog: [String] = []
    public var kernelHandle: KernelRwHandle?

    @ObservationIgnored public lazy var exploitViewModel = ExploitViewModel(coordinator: self)

    public init() {
        // Reject unsupported devices immediately
        if !deviceInfo.isSupported {
            appState = .exploitFailed("iOS \(deviceInfo.systemVersion) is not supported. Requires 17.0 – 26.0.")
            return
        }
        if UserDefaults.standard.bool(forKey: Self.panicFlagKey) {
            // Previous session set the flag but never cleared it → likely a kernel panic.
            // Keep the flag set until user acknowledges so the panic screen shows on
            // every launch until they tap OK.
            appState = .panicRecovery
        }
    }

    public func appendLog(_ message: String) {
        exploitLog.append(message)
        print("[TrollStore] \(message)")
    }

    public func startPipeline() {
        guard deviceInfo.isSupported else {
            handleExploitFailure("Device unsupported: \(deviceInfo.modelIdentifier) on iOS \(deviceInfo.systemVersion)")
            return
        }
        UserDefaults.standard.set(true, forKey: Self.panicFlagKey)
        appState = .obtainingOffsets
        appendLog("Starting pipeline — resolving kernel offsets...")
        exploitViewModel.currentStage = .downloadingKernelCache
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = XPFWrapper.ensureInitialized()
            DispatchQueue.main.async {
                guard let self = self else { return }
                if ok {
                    self.exploitViewModel.currentStage = .runningXPF
                    self.appendLog("Offsets resolved — starting exploit")
                    self.appState = .exploiting
                    self.exploitViewModel.continueExploit()
                } else {
                    self.handleExploitFailure("XPF offset resolution failed — no kernelcache available")
                }
            }
        }
    }

    /// User acknowledged the panic recovery screen. Clear the flag so the
    /// app returns to the normal .sandboxed start on next launch.
    public func acknowledgePanic() {
        UserDefaults.standard.set(false, forKey: Self.panicFlagKey)
        appState = .sandboxed
        appendLog("Panic acknowledged — returning to sandboxed state")
    }

    public func handleExploitSuccess(with handle: KernelRwHandle) {
        UserDefaults.standard.set(false, forKey: Self.panicFlagKey)
        kernelHandle = handle
        appendLog("Kernel r/w established — initializing offsets...")

        // Initialize all kernel structure offsets for the current iOS version
        // and SoC family. Without this, every post-exploit C module (sbx, vfs,
        // vnode, RemoteCall) will use zero offsets and corrupt kernel memory.
        offsets_init()
        appendLog("Kernel offsets initialized")

        let kernelBase = XPFWrapper.findKernelBase()
        guard kernelBase > 0 else {
            handleExploitFailure("Kernel base resolution failed — cannot patch")
            return
        }
        let patcher = KernelPatcher(handle: handle, kernelBase: kernelBase)
        guard patcher.applyAll() else {
            handleExploitFailure("AMFI patch failed")
            return
        }

        guard let escape = SandboxEscape(handle: handle, kernelBase: kernelBase) else {
            handleExploitFailure("SandboxEscape init failed")
            return
        }
        guard escape.clearSandbox() else {
            handleExploitFailure("Sandbox escape failed")
            return
        }

        guard VirtualFileSystem.initialize() else {
            handleExploitFailure("VFS init failed")
            return
        }

        appState = .patched
        exploitViewModel.currentStage = .complete
        exploitViewModel.isRunning = false
        appendLog("System ready — full access granted ✓")
    }

    public func handleExploitFailure(_ reason: String) {
        UserDefaults.standard.set(false, forKey: Self.panicFlagKey)
        appState = .exploitFailed(reason)
        exploitViewModel.isRunning = false
        exploitViewModel.currentStage = .failed
        appendLog("FAILED: \(reason)")
    }

    public func handlePanic() {
        appState = .panicRecovery
        appendLog("Kernel panic detected — device may reboot")
    }
}

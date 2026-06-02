import SwiftUI

@MainActor
public final class ContentCoordinator: ObservableObject {
    /// Shared UserDefaults key used for kernel-panic detection across app launches.
    public static let panicFlagKey = "com.trollstoredarksword.exploitRunning"
    public let deviceInfo = DeviceInfo.current
    @Published public var appState: AppState = .sandboxed
    @Published public var exploitLog: [String] = []
    @Published public var kernelHandle: KernelRwHandle?
    @Published public var pendingIPAURL: URL?
    /// User-facing error message when an IPA import fails.
    @Published public var importError: String?
    /// Currently selected tab in PatchedView.
    @Published public var persistInstallation = true
    /// Tracks if the user has dismissed the exploit success screen.
    @Published public var hasSeenSuccess = false
    @Published public var selectedTab: Tab = .home

    public enum Tab: Int, CaseIterable {
        case home = 0
        case apps = 1
        case install = 2
        case activity = 3
        case settings = 4

        public var label: String {
            switch self {
            case .home: return "Home"
            case .apps: return "Apps"
            case .install: return "Install"
            case .activity: return "Activity"
            case .settings: return "Settings"
            }
        }

        public var systemImage: String {
            switch self {
            case .home: return "house.fill"
            case .apps: return "square.grid.2x2"
            case .install: return "arrow.down.to.line"
            case .activity: return "chart.xyaxis.line"
            case .settings: return "gearshape.fill"
            }
        }
    }

    @Published public var activityEntries: [ActivityEntry] = []

    public lazy var exploitViewModel = ExploitViewModel(coordinator: self)

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
        exploitViewModel.logEntries.append("[\(Date().formatted(date: .omitted, time: .standard))] \(message)")
        LogManager.shared.append(message, tag: "Pipeline")
        appendActivity(ActivityEntry(message: message, type: .info))
    }

    public func appendActivity(_ entry: ActivityEntry) {
        activityEntries.insert(entry, at: 0)
        if activityEntries.count > 50 {
            activityEntries = Array(activityEntries.prefix(50))
        }
    }

    public func startPipeline() {
        LogManager.shared.startNewSession()
        hasSeenSuccess = false
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

        // Step 0: Cache SpringBoard PID pre-exploit via BSD-only proc_name()
        // (NO krw, NO proc linked-list walking). This PID is used post-exploit
        // for page-scan resolution, avoiding any krw-based process lookup that
        // could panic the kernel via DarkSword-corrupted proc list pointers.
        let sbPid = find_pid_by_name_safe("SpringBoard")
        if sbPid > 0 {
            save_cached_pid("SpringBoard", sbPid)
            appendLog("SpringBoard PID cached: \(sbPid)")
        } else {
            appendLog("Warning: SpringBoard PID not found pre-exploit — page-scan will search by name")
        }

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

                    // Validate critical struct offsets before running exploit
                    if !XPFWrapper.validateCriticalOffsets() {
                        self.appendLog("WARNING: icmp6_filter offset may be wrong for this build")
                        self.appendLog("If the exploit hangs, try setting a custom offset in Settings \u{2192} Modify Offsets")
                        LogManager.shared.append("WARNING: icmp6_filter offset may be wrong for this build", tag: "Pipeline")
                        LogManager.shared.append("If the exploit hangs, try setting a custom offset in Settings \u{2192} Modify Offsets", tag: "Pipeline")
                    }

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
        // Panic flag intentionally NOT cleared here — it stays set until all pipeline
        // steps complete. If the kernel panics during patching/offsets/sandbox-escape,
        // the next launch detects it via .panicRecovery. Cleared on final success below.
        kernelHandle = handle
        appendActivity(ActivityEntry(message: "Kernel r/w established", type: .success))
        appendLog("Kernel r/w established — resolving kernel base...")

        // Socket recreation check
        if !ds_sockets_recreated() {
            appendLog("WARNING: krw sockets were NOT recreated — old corrupted sockets in use")
            appendLog("Kernel panic likely on next ICMPv6 setsockopt/getsockopt")
        }

        // Step 1: Resolve kernel base via XPF (BEFORE offsets_init, which
        // destroys XPF). Both applyAll() and findKernelBase() need gXPF alive.
        print("[D] handleExploitSuccess: calling findKernelBase...")
        let kernelBase = XPFWrapper.findKernelBase()
        print("[D] findKernelBase returned 0x\(String(kernelBase, radix: 16))")
        guard kernelBase > 0 else {
            handleExploitFailure("Kernel base resolution failed — cannot patch")
            return
        }

        // Step 2: Apply kernel patches.
        // First: P_PLATFORM flag (critical — halts pipeline on failure).
        // Second: mac_proc_enforce = 0 (additive — non-fatal, extra defense layer).
        appendLog("Kernel base resolved — applying patches...")
        let patcher = KernelPatcher(handle: handle, kernelBase: kernelBase)
        print("[D] handleExploitSuccess: calling patcher.applyAll...")
        guard patcher.applyAll() else {
            handleExploitFailure("Kernel patching failed — invalid kernel base")
            return
        }
        appendActivity(ActivityEntry(message: "Kernel patches applied", type: .success))
        print("[D] patcher.applyAll SUCCEEDED")

        // Also zero mac_proc_enforce as a complementary AMFI bypass.
        // Non-fatal: P_PLATFORM alone is sufficient on most versions.
        // getmacprocenforceoff() looks for the kernel cache at Documents/kernelcache,
        // so copy it there from wherever XPF loaded it.
        if let kcPath = XPFWrapper.currentKernelCachePath {
            let docsKc = NSHomeDirectory() + "/Documents/kernelcache"
            if !FileManager.default.fileExists(atPath: docsKc) {
                try? FileManager.default.copyItem(atPath: kcPath, toPath: docsKc)
            }
        } else {
            appendLog("XPF kernel cache path not available — mac_proc_enforce resolution may fail")
        }
        if patcher.disableMACProcEnforce() {
            appendLog("mac_proc_enforce zeroed — extra AMFI defense ✓")
        } else {
            appendLog("mac_proc_enforce not zeroed — P_PLATFORM still active")
        }

        // Step 3: Initialize kernel structure offsets for post-exploit C modules
        // (sbx, vfs, vnode, RemoteCall). offsets_init calls xpf_stop() internally,
        // destroying gXPF, but we no longer need XPF after this point.
        //
        // NOTE: offsets_init() was ALREADY called inside pe_v1()/pe_a18() during
        // ds_run() to resolve socket struct offsets before they're needed by
        // krw_sockets_leak_forever. This second call re-runs loadalloffsets()
        // which applies any NSUserDefaults overrides the user may have set —
        // so it's intentional, not a duplicate.
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
        exploitViewModel.currentStage = .escapingSandbox
        guard let escape = SandboxEscape(handle: handle, kernelBase: kernelBase, kernprocAddr: kernprocAddr) else {
            handleExploitFailure("SandboxEscape init failed")
            return
        }
        guard escape.clearSandbox() else {
            handleExploitFailure("Sandbox escape failed")
            return
        }
        appendActivity(ActivityEntry(message: "Sandbox escaped", type: .success))

        // Developer mode detection for diagnostics (iOS 16+)
        var devModeEnabled: Int = 0
        var size = MemoryLayout<Int>.size
        let result = sysctlbyname("kern.developermode.status", &devModeEnabled, &size, nil, 0)
        if result == 0 {
            appendLog("Developer mode: \(devModeEnabled > 0 ? "enabled" : "disabled")")
        } else {
            appendLog("Developer mode: could not query (sysctl returned \(result))")
        }

        // Step 5: VFS init (needs offsets from step 3)
        guard VirtualFileSystem.initialize() else {
            handleExploitFailure("VFS init failed")
            return
        }
        appendActivity(ActivityEntry(message: "VFS initialized — system ready", type: .success))

        // Step 6: Resolve SpringBoard proc address for krw-free RemoteCall init.
        // The DarkSword race corrupts 0x40 bytes of random proc structs, including
        // p_pid. safe_procbypid(34) CAN return a false-positive match — a corrupted
        // proc whose p_pid was randomly overwritten to 34 but whose p_proc_ro/p_task
        // is garbage. Using such a proc would fail initRemoteCallWithProc:.
        //
        // Strategy (in order):
        //   1. safe_procbypid + p_name validation — lightweight krw linked-list walk
        //      with user-space pointer validation, THEN p_name read to confirm identity.
        //      Catches false-positive PID matches from DarkSword corruption.
        //   2. proc_find_by_page_scan — linear kernel memory scan at 0x40 stride,
        //      never follows linked-list pointers. Validates BOTH p_pid AND p_name
        //      per candidate. Immune to false-positive matches and linked-list
        //      corruption. Does NOT need a cached PID — matches by name.
        //
        // Note: pre-exploit find_pid_by_name_safe often fails (proc_name() is gated
        // by AMFI for sandboxed apps on iOS 18), so get_cached_pid() returns 0.
        // Step 6 runs regardless — safe_procbypid uses the cached PID if available,
        // page-scan works by name alone.

        // Phase A: safe_procbypid + name validation (fast — uses cached PID)
        var sbProcAddr: UInt64 = 0
        let cachedPid = get_cached_pid("SpringBoard")
        if cachedPid > 0 {
            sbProcAddr = safe_procbypid(cachedPid)
            sbProcAddr = validate_proc_by_name(sbProcAddr, "SpringBoard")
        }

        // Phase B: page-scan if safe_procbypid failed (immune to list corruption)
        if sbProcAddr == 0 {
            appendLog("safe_procbypid failed — trying page-scan...")
            sbProcAddr = proc_find_by_page_scan("SpringBoard")
        }

        if sbProcAddr > 0 {
            save_cached_proc_addr("SpringBoard", sbProcAddr)
            appendLog("SpringBoard proc resolved: 0x\(String(sbProcAddr, radix: 16))")
        } else {
            appendLog("Warning: SpringBoard proc not found — RemoteCall will fail gracefully")
        }

        // All pipeline steps succeeded — clear the panic flag.
        UserDefaults.standard.set(false, forKey: Self.panicFlagKey)
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
        appendActivity(ActivityEntry(message: "Exploit failed: \(reason)", type: .error))
        appendLog("FAILED: \(reason)")
    }

    public func handlePanic() {
        appState = .panicRecovery
        appendLog("Kernel panic detected — device may reboot")
    }

    public func handleImportedIPA(_ url: URL) {
        importError = nil
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ipa")
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            pendingIPAURL = dest
            appendLog("Received IPA — pending installation")
        } catch {
            importError = "Failed to import IPA: \(error.localizedDescription)"
            appendLog("Failed to copy shared IPA: \(error.localizedDescription)")
        }
    }
}

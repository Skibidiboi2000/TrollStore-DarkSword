import Foundation

public enum XPFWrapper {
    private nonisolated(unsafe) static var kernelCachePath: String?

    /// Thread-safe read of XPF kernel version via C helper.
    private static var xpfVersionString: String? {
        choma_xpf_version_string().flatMap { String(cString: $0) }
    }

    /// Thread-safe read of XPF kernel base via C helper.
    private static var xpfKernelBase: UInt64 {
        choma_xpf_kernel_base()
    }

    private static let initLock: NSLock = {
        let lock = NSLock()
        lock.name = "com.trollstoredarksword.xpf-init"
        return lock
    }()

    /// Ensure XPF is initialized: grab the kernel cache and start XPF.
    /// Returns true if XPF is ready for symbol resolution.
    @discardableResult
    public static func ensureInitialized() -> Bool {
        initLock.lock()
        if let _ = kernelCachePath { initLock.unlock(); return true }
        guard let kcPath = obtainKernelCache() else { initLock.unlock(); return false }
        let result = xpf_start_with_kernel_path((kcPath as NSString).utf8String)
        guard result == 0 else {
            let errMsg: String
            if let errPtr = xpf_get_error() {
                errMsg = String(cString: errPtr)
            } else {
                errMsg = "unknown error (xpf_get_error returned NULL)"
            }
            LogManager.shared.append("xpf_start failed: \(errMsg)", tag: "XPF")
            initLock.unlock()
            return false
        }
        kernelCachePath = kcPath
        initLock.unlock()
        if let verStr = xpfVersionString {
            LogManager.shared.append("Initialized: \(verStr)", tag: "XPF")
        }
        return true
    }

    /// Obtain the kernel cache: try local paths first, then download.
    private static func obtainKernelCache() -> String? {
        let localPaths = [
            "/System/Library/Caches/com.apple.kernelcaches/kernelcache",
            "/System/Library/Caches/com.apple.kernelcaches/kernelcaches",
        ]
        for path in localPaths {
            if FileManager.default.fileExists(atPath: path) { return path }
        }

        let tmpPath = NSTemporaryDirectory().appending("kernelcache")
        if grab_kernelcache(tmpPath) {
            return tmpPath
        }
        return nil
    }

    /// Resolve an XPF kernel symbol to its absolute address.
    private static func resolveSymbol(_ name: String) -> UInt64? {
        guard ensureInitialized() else { return nil }
        let addr = xpf_item_resolve(name)
        guard addr > 0 else { return nil }
        return addr
    }

    /// Find AMFIIsCDHashInTrustCache address using XPF.
    public static func findAMFIPatchOffset() -> UInt64? {
        guard ensureInitialized() else { return nil }
        let symbols = [
            "AMFI",
            "AMFIIsCDHashInTrustCache",
            "_AMFIIsCDHashInTrustCache",
            "AMFITrustCache",
            "AMFI:TrustCache",
        ]
        for name in symbols {
            if let addr = resolveSymbol(name) {
                LogManager.shared.append("AMFI symbol resolved via \(name) at 0x\(String(addr, radix: 16))", tag: "XPF")
                return addr
            }
        }
        return nil
    }

    /// Find developer_mode_status variable address.
    public static func findDevModeStatus() -> UInt64? {
        guard ensureInitialized() else { return nil }
        if let addr = resolveSymbol("developer_mode_status") {
            return addr
        }
        return nil
    }

    /// Find current_task address.
    public static func findCurrentTask() -> UInt64? {
        if let addr = resolveSymbol("kernelSymbol.kernproc") {
            return addr
        }
        return nil
    }

    /// Get kernel base from XPF or fallback.
    /// Run a direct PatchFinder scan and pipe diagnostics into LogManager.
    /// - Parameters:
    ///   - finder: The C function to call (e.g. choma_find_amfi_function_direct)
    ///   - name: Human-readable label for logs
    /// - Returns: Kernel address or nil
    private static func runDirectFinder(_ finder: () -> UInt64, name: String) -> UInt64? {
        guard ensureInitialized() else {
            if let err = xpf_get_error() {
                LogManager.shared.append("\(name): XPF not initialized: \(String(cString: err))", tag: "XPF")
            }
            return nil
        }
        print("[D] runDirectFinder(\(name)): calling C finder...")
        let addr = finder()
        if let diagStr = choma_drain_diagnostics() {
            let s = String(cString: diagStr)
            if !s.isEmpty {
                for line in s.split(separator: "\n") { LogManager.shared.append(String(line), tag: "CHOMA") }
            }
        }
        if addr > 0 {
            LogManager.shared.append("\(name) resolved via direct PatchFinder at 0x\(String(addr, radix: 16))", tag: "XPF")
        } else if let err = xpf_get_error() {
            LogManager.shared.append("\(name) failed: \(String(cString: err))", tag: "XPF")
        } else {
            LogManager.shared.append("\(name) failed (no error string)", tag: "XPF")
        }
        return addr > 0 ? addr : nil
    }

    /// Invalidate the cached XPF state.
    /// Call this after offsets_init() calls xpf_stop(), which destroys gXPF.
    /// The next ensureInitialized() call will restart XPF from scratch.
    public static func resetXPF() {
        initLock.lock()
        kernelCachePath = nil
        initLock.unlock()
    }

    /// Fallback: find developer_mode_status variable address using direct
    /// PatchFinder scan. Used when libxpf's symbol resolution fails.
    public static func findDevModeStatusDirect() -> UInt64? {
        return runDirectFinder({ choma_find_dev_mode_status_direct() }, name: "developer_mode_status")
    }

    /// Get the VM address of AMFI's primary data section.
    /// Returns 0 if AMFI entry not found.
    public static func getAMFIDataRange() -> (start: UInt64, size: UInt64) {
        _ = ensureInitialized()
        var size: UInt64 = 0
        let start = choma_get_amfi_data_range(&size)
        return (start, size)
    }

    /// Find the trust cache module header by scanning the kernel's on-disk
    /// __DATA_CONST,__data section for the version/UUID/count pattern.
    /// Returns the UNSLID VM address; caller must add KASLR slide.
    public static func findTrustCacheByDataScan() -> UInt64? {
        guard ensureInitialized() else {
            if let err = xpf_get_error() { LogManager.shared.append("findTrustCacheByDataScan: XPF not initialized: \(String(cString: err))", tag: "XPF") }
            return nil
        }
        let addr = choma_find_trust_cache_by_data_scan()
        // Drain ChOma diagnostics (if any) even on success — they may contain
        // useful info about the scan process.
        if let diagStr = choma_drain_diagnostics() {
            let s = String(cString: diagStr)
            if !s.isEmpty { for line in s.split(separator: "\n") { LogManager.shared.append(String(line), tag: "CHOMA") } }
        }
        if let err = xpf_get_error() {
            LogManager.shared.append("findTrustCacheByDataScan: \(String(cString: err))", tag: "XPF")
        }
        guard addr > 0 else { return nil }
        return addr
    }

    /// Find the ppl_trust_cache_rt runtime structure address
    /// by locating a unique panic string and tracing ADRP references.
    public static func findTrustCacheRuntime() -> UInt64? {
        guard ensureInitialized() else {
            if let err = xpf_get_error() { LogManager.shared.append("findTrustCacheRuntime: XPF not initialized: \(String(cString: err))", tag: "XPF") }
            return nil
        }
        let addr = choma_find_trust_cache_runtime()
        if let diagStr = choma_drain_diagnostics() {
            let s = String(cString: diagStr)
            if !s.isEmpty { for line in s.split(separator: "\n") { LogManager.shared.append(String(line), tag: "CHOMA") } }
        }
        if let err = xpf_get_error() {
            LogManager.shared.append("findTrustCacheRuntime: \(String(cString: err))", tag: "XPF")
        }
        if addr > 0 {
            LogManager.shared.append("Trust cache found at unslid 0x\(String(addr, radix: 16))", tag: "XPF")
        }
        guard addr > 0 else { return nil }
        return addr
    }

    public static func findKernelBase() -> UInt64 {
        if ensureInitialized() {
            let base = xpfKernelBase
            print("[D] findKernelBase: xpfKernelBase = 0x\(String(base, radix: 16))")
            if base > 0 { return base }
        }
        if ds_is_ready() {
            let base = ds_get_kernel_base()
            if base > 0 { return base }
        }
        return 0
    }
}

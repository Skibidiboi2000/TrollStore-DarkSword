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

    /// The path to the kernel cache XPF is currently using.
    /// nil if XPF hasn't been initialized yet.
    public static var currentKernelCachePath: String? {
        initLock.lock()
        let p = kernelCachePath
        initLock.unlock()
        return p
    }

    /// Invalidate the cached XPF state.
    /// Call this after offsets_init() calls xpf_stop(), which destroys gXPF.
    /// The next ensureInitialized() call will restart XPF from scratch.
    public static func resetXPF() {
        initLock.lock()
        kernelCachePath = nil
        initLock.unlock()
    }

    /// Verify a struct offset against XPF resolution from kernelcache.
    /// Returns true if the offset matches the expected value, false with a
    /// warning if they differ (the hardcoded offset may be wrong for this build).
    /// Requires XPF to be initialized (ensureInitialized()).
    public static func validateStructOffset(named: String, expected: UInt32) -> Bool {
        guard ensureInitialized() else {
            LogManager.shared.append("XPF not initialized -- cannot validate \(named)", tag: "XPF")
            return false
        }
        let resolved = xpf_item_resolve(named)
        guard resolved > 0 else {
            LogManager.shared.append("XPF cannot resolve \(named) -- this kernelcache may lack this symbol", tag: "XPF")
            return false
        }
        let match = resolved == UInt64(expected)
        if !match {
            LogManager.shared.append(
                "\u{26A0}\u{FE0F} OFFSET MISMATCH: \(named) expected=0x\(String(expected, radix: 16)) xpf=0x\(String(resolved, radix: 16))",
                tag: "XPF"
            )
        }
        return match
    }

    /// Validate all critical struct offsets against XPF.
    /// Logs warnings for any mismatches. Returns false if ANY critical offset
    /// (icmp6filt) is mismatched.
    public static func validateCriticalOffsets() -> Bool {
        // inp_icmp6filter -- critical for exploit krw path.
        // Non-fatal for now: XPF struct offset naming may differ from the actual
        // symbol path in XPF's database, so a "not found" result is expected.
        validateStructOffset(
            named: "inp_depend6.inp6_icmp6filt",
            expected: get_off_inpcb_inp_depend6_inp6_icmp6filt()
        )
    }

    /// Auto-override hardcoded offsets with XPF-resolved values using the
    /// existing NSUserDefaults-based override mechanism in offsets.m.
    ///
    /// Call this after ensureInitialized() and BEFORE offsets_init() so that
    /// loadalloffsets() inside offsets_init picks up the corrected values.
    ///
    /// Maps XPF struct member paths to the UserDefaults keys used by offsets.m
    /// (format: "lara.offset.off_<struct>_<field>").
    public static func applyXPFOffsetOverrides() {
        guard ensureInitialized() else { return }
        let defaults = UserDefaults.standard
        let mappings: [(xpfSymbol: String, udKey: String, is64: Bool, oldValPtr: UnsafeRawPointer?)] = [
            ("inp_depend6.inp6_icmp6filt",  "lara.offset.off_inpcb_inp_depend6_inp6_icmp6filt",  false, nil),
            ("inp_list_le_next",            "lara.offset.off_inpcb_inp_list_le_next",              false, nil),
            ("inp_pcbinfo",                 "lara.offset.off_inpcb_inp_pcbinfo",                    false, nil),
            ("inp_socket",                  "lara.offset.off_inpcb_inp_socket",                     false, nil),
            ("so_usecount",                 "lara.offset.off_socket_so_usecount",                   false, nil),
            ("so_proto",                    "lara.offset.off_socket_so_proto",                      false, nil),
            ("pr_input",                    "lara.offset.off_protosw_pr_input",                     false, nil),
        ]

        var overriddenCount = 0
        for (sym, key, _, _) in mappings {
            guard !sym.isEmpty else { continue }
            let resolved = xpf_item_resolve(sym)
            guard resolved > 0 else { continue }

            let oldValue: UInt32
            if let ptr = getOffsetsPtr(for: key) {
                oldValue = ptr.pointee
            } else {
                oldValue = UInt32(defaults.integer(forKey: key))
            }

            if oldValue != UInt32(resolved) {
                defaults.set(Int32(resolved), forKey: key)
                overriddenCount += 1
                LogManager.shared.append(
                    "XPF override: \(sym) → 0x\(String(resolved, radix: 16)) (was 0x\(String(oldValue, radix: 16)))",
                    tag: "XPF"
                )
            }
        }

        if overriddenCount > 0 {
            defaults.synchronize()
            LogManager.shared.append("Applied \(overriddenCount) XPF offset overrides", tag: "XPF")
        }
    }

    /// Look up a C global offset variable's address by its UserDefaults key pattern.
    /// Returns nil for symbols that aren't exposed via the C global table.
    private static func getOffsetsPtr(for key: String) -> UnsafeMutablePointer<UInt32>? {
        // The C globals (off_inpcb_inp_depend6_inp6_icmp6filt etc.) are declared
        // in offsets.m. We can't easily look them up by name at runtime.
        // Instead, we rely on NSUserDefaults readback by loadalloffsets().
        return nil
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

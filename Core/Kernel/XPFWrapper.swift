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

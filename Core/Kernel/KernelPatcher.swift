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
    ]
    private static let pPlatform: UInt32 = 0x80000000

    // Trust cache v2 layout (trust_cache_module1):
    //   +0:  version (4 bytes) = 2
    //   +4:  UUID (16 bytes)
    //   +20: num_entries (4 bytes)
    //   +24: entries[] (stride = 24 bytes each)
    //
    // Each entry (trust_cache_entry1, stride=24):
    //   bytes 0-19:  CDHash (20 bytes)
    //   byte  20:    hash_type (2 = SHA256)
    //   byte  21:    flags (0 = normal, 4 = platform binary)
    //   bytes 22-23: padding
    private static let TC_HEADER_SIZE: UInt64 = 24
    private static let TC_ENTRY_STRIDE: UInt64 = 24

    // SENTINEL for write test (DSPloit pattern)
    private static let TC_SENTINEL: UInt64 = 0xDEADBEEFCAFEBABE

    // CS_OPS_CDHASH constant from cs_blobs.h
    private static let CS_OPS_CDHASH: UInt32 = 6
    // CS_CDHASH_LEN = 20 (SHA1) under CS_HASHTYPE_SHA1
    private static let CS_CDHASH_LEN = 20

    // Declare the csops syscall (4th param is size_t by value)
    @_silgen_name("csops")
    private static func csops(_ pid: pid_t, _ ops: UInt32, _ addr: UnsafeMutableRawPointer, _ size: Int) -> Int32

    public init(handle: KernelRwHandle, kernelBase: UInt64) {
        self.handle = handle
        self.kernelBase = kernelBase
    }

    // -----------------------------------------------------------------------
    // Direct trust cache injection (DSPloit approach)
    // -----------------------------------------------------------------------

    /// Inject our app's CDHash directly into the kernel's trust cache data
    /// using the DSPloit 3-phase pattern: write-test → inject → verify count.
    ///
    /// This replaces the previous approach of trying to find and patch
    /// AMFIIsCDHashInTrustCache, which fails on iOS 18.2+ (function name
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
    // CDHash helpers
    // -----------------------------------------------------------------------

    /// Get the current process's CDHash via csops syscall.
    /// This returns the same hash the kernel uses for trust cache lookups.
    private func computeOurCDHash() -> [UInt8]? {
        var cdhash = [UInt8](repeating: 0, count: Self.CS_CDHASH_LEN)
        let ret = Self.csops(getpid(), Self.CS_OPS_CDHASH, &cdhash, Self.CS_CDHASH_LEN)
        guard ret == 0 else {
            LogManager.shared.append("csops(CS_OPS_CDHASH) failed: \(ret)", tag: "KernelPatcher")
            return nil
        }
        return cdhash
    }

    // -----------------------------------------------------------------------
    // KRW helpers
    // -----------------------------------------------------------------------

    private func readUInt64(_ addr: UInt64) -> UInt64? {
        guard let data = handle.kread(addr, 8) else { return nil }
        return data.withUnsafeBytes { $0.load(as: UInt64.self) }
    }

    @discardableResult
    private func writeUInt64(_ addr: UInt64, _ value: UInt64) -> Bool {
        var val = value
        let data = Data(bytes: &val, count: 8)
        return handle.kwrite(addr, data)
    }

    // -----------------------------------------------------------------------
    // Developer mode patching
    // -----------------------------------------------------------------------

    /// Enable developer mode by setting the developer_mode_status variable.
    @discardableResult
    public func enableDeveloperMode() -> Bool {
        // Strategy chain: XPF symbols → choma direct PatchFinder → data-scan fallback
        if let address = XPFWrapper.findDevModeStatus() ?? XPFWrapper.findDevModeStatusDirect() {
            return writeDevModeValue(address)
        }

        LogManager.shared.append("Trying data-section brute-force for developer_mode_status...", tag: "KernelPatcher")

        // Fallback: scan AMFI's data section for 4-byte globals via kernel-r/w
        if let address = findDevModeViaDataScan() {
            LogManager.shared.append("Found developer_mode_status at 0x\(String(address, radix: 16)) via data scan", tag: "KernelPatcher")
            return writeDevModeValue(address)
        }

        LogManager.shared.append("Could not find developer_mode_status", tag: "KernelPatcher")
        return false
    }

    /// Scan AMFI's data section at runtime for the developer_mode_status variable.
    /// Heuristic: look for a uint32 = 0 at a 4-aligned address that's the ONLY
    /// zero field in a struct (preceded and followed by non-zero data).
    /// Returns the address of the variable, or nil.
    private func findDevModeViaDataScan() -> UInt64? {
        let (dataStart, dataSize) = XPFWrapper.getAMFIDataRange()
        guard dataStart > 0, dataSize >= 64 else { return nil }

        // Read the entire data section (up to 8 pages)
        let readSize = min(dataSize, 0x8000)
        guard let sectionData = handle.kread(dataStart, Int(readSize)) else { return nil }

        let raw = [UInt8](sectionData)
        let count = raw.count / 4

        // Heuristic: find a 4-byte zero that:
        // 1. Has non-zero data before and after it (not at struct boundary)
        // 2. Is 4-byte aligned
        // 3. Is near other non-zero values (part of a struct, not empty memory)
        var candidates: [(offset: Int, score: Int)] = []

        for i in 0..<(count - 2) {
            let off = i * 4
            let val = UInt32(raw[off]) | (UInt32(raw[off+1]) << 8) |
                      (UInt32(raw[off+2]) << 16) | (UInt32(raw[off+3]) << 24)
            guard val == 0 else { continue }

            // Score this candidate
            var score = 0
            // Check surrounding dwords
            let prev = i > 0 ? (UInt32(raw[(i-1)*4]) | (UInt32(raw[(i-1)*4+1]) << 8) |
                                (UInt32(raw[(i-1)*4+2]) << 16) | (UInt32(raw[(i-1)*4+3]) << 24)) : 0
            let next = (i + 1 < count) ? (UInt32(raw[(i+1)*4]) | (UInt32(raw[(i+1)*4+1]) << 8) |
                                           (UInt32(raw[(i+1)*4+2]) << 16) | (UInt32(raw[(i+1)*4+3]) << 24)) : 0

            // Prefer: surrounded by non-zero (likely struct), not surrounded by zero (likely padding)
            if prev != 0 { score += 1 }
            if next != 0 { score += 1 }

            // Bonus: next dword is 0 or 1 (developer_mode_status often followed by another flag)
            if next == 0 || next == 1 { score += 2 }

            // Bonus: small values nearby (flags/enums)
            for j in max(0, i-3)...min(count-1, i+3) where j != i {
                let v = UInt32(raw[j*4]) | (UInt32(raw[j*4+1]) << 8) |
                        (UInt32(raw[j*4+2]) << 16) | (UInt32(raw[j*4+3]) << 24)
                if v < 8 { score += 1 }
            }

            if score >= 3 {
                candidates.append((off, score))
            }
        }

        // Sort by score, try each candidate by writing 2 and checking
        candidates.sort { $0.score > $1.score }
        let maxTries = min(candidates.count, 5)

        for i in 0..<maxTries {
            let addr = dataStart + UInt64(candidates[i].offset)
            // Try writing 2
            var val: UInt32 = 2
            let writeData = Data(bytes: &val, count: 4)
            guard handle.kwrite(addr, writeData) else { continue }

            // Verify write
            if let checkData = handle.kread(addr, 4) {
                let readVal = checkData.withUnsafeBytes { $0.load(as: UInt32.self) }
                if readVal == 2 {
                    // Restore original (0) for now — caller will persist if correct
                    // Actually leave it as 2, caller can verify
                    LogManager.shared.append("Found candidate dev mode addr at 0x\(String(addr, radix: 16)) score=\(candidates[i].score)", tag: "KernelPatcher")
                    return addr
                }
            }
        }

        return nil
    }

    private func writeDevModeValue(_ address: UInt64) -> Bool {
        var value: UInt32 = 2
        let data = Data(bytes: &value, count: 4)

        guard handle.kwrite(address, data) else {
            LogManager.shared.append("Failed to set developer_mode_status", tag: "KernelPatcher")
            return false
        }

        guard let verifyData = handle.kread(address, 4),
              verifyData.withUnsafeBytes({ $0.load(as: UInt32.self) }) == 2 else {
            LogManager.shared.append("developer_mode_status verification failed", tag: "KernelPatcher")
            return false
        }

        LogManager.shared.append("Developer mode enabled ✓", tag: "KernelPatcher")
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
    /// Unlike previous approaches, this does NOT attempt to disable MAC process
    /// enforcement (mac_proc_enforce), AMFI code signing, or set developer mode
    /// via XPF — because all of those either crash, corrupt exploit state, or
    /// write to wrong addresses. Instead, we only set P_PLATFORM on our process
    /// (if proc resolution works) and let the caller continue with offsets_init,
    /// sandbox escape, and VFS init (the LARA approach).
    ///
    /// Returns true as long as kernelBase is valid (the exploit is stable).
    @discardableResult
    public func applyAll() -> Bool {
        print("[D] applyAll: kernelBase = 0x\(String(kernelBase, radix: 16))")
        LogManager.shared.append("applyAll started", tag: "KernelPatcher")
        guard kernelBase > 0 else {
            LogManager.shared.append("Invalid kernelBase: cannot patch", tag: "KernelPatcher")
            return false
        }
        // Set P_PLATFORM flag on our process (uses only kernel r/w, no XPF)
        let platformOK = enablePlatformApplication()
        if platformOK {
            LogManager.shared.append("P_PLATFORM set on our process ✓", tag: "KernelPatcher")
        } else {
            LogManager.shared.append("Could not set P_PLATFORM — proc address may not be resolvable", tag: "KernelPatcher")
        }
        return true
    }
}

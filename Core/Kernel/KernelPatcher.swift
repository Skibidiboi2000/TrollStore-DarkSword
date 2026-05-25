import Foundation
import OSLog

public final class KernelPatcher {
    private let handle: KernelRwHandle
    private let kernelBase: UInt64

    public init(handle: KernelRwHandle, kernelBase: UInt64) {
        self.handle = handle
        self.kernelBase = kernelBase
    }

    /// Patch AMFIIsCDHashInTrustCache to always return true.
    /// Before: Full function with prologue (SUB SP, SP, #0x40; ...)
    /// After:  MOV X0, #1 ; RET
    ///
    /// The patch bytes for arm64e (A14):
    ///   MOV X0, #1  → 20 00 80 D2
    ///   RET         → C0 03 5F D6
    @discardableResult
    public func patchAMFITrustCache() -> Bool {
        guard let address = XPFWrapper.findAMFIPatchOffset() else {
            print("[KernelPatcher] Could not find AMFI function address")
            return false
        }

        // arm64e: mov x0, #1; ret
        let patchBytes: Data = Data([0x20, 0x00, 0x80, 0xD2, 0xC0, 0x03, 0x5F, 0xD6])

        guard handle.kwrite(address, patchBytes) else {
            print("[KernelPatcher] Failed to write AMFI patch")
            return false
        }

        // Verify by reading back
        guard let verifyData = handle.kread(address, 8), verifyData == patchBytes else {
            print("[KernelPatcher] AMFI patch verification failed")
            return false
        }

        print("[KernelPatcher] AMFIIsCDHashInTrustCache patched ✓")
        return true
    }

    /// Enable developer mode by setting the developer_mode_status variable.
    @discardableResult
    public func enableDeveloperMode() -> Bool {
        guard let address = XPFWrapper.findDevModeStatus() else {
            print("[KernelPatcher] Could not find developer_mode_status")
            return false
        }

        var value: UInt32 = 2
        let data = Data(bytes: &value, count: 4)

        guard handle.kwrite(address, data) else {
            print("[KernelPatcher] Failed to set developer_mode_status")
            return false
        }

        // Verify
        guard let verifyData = handle.kread(address, 4),
              verifyData.withUnsafeBytes({ $0.load(as: UInt32.self) }) == 2 else {
            print("[KernelPatcher] developer_mode_status verification failed")
            return false
        }

        print("[KernelPatcher] Developer mode enabled ✓")
        return true
    }

    /// Apply both kernel patches.
    @discardableResult
    public func applyAll() -> Bool {
        guard kernelBase > 0 else {
            print("[KernelPatcher] Invalid kernelBase: cannot patch")
            return false
        }
        let amfiOK = patchAMFITrustCache()
        if !enableDeveloperMode() {
            os_log(.error, "developer mode not enabled — platform-application entitlements may be rejected at launch")
        }
        return amfiOK
    }
}

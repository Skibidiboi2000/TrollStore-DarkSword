import Foundation

class KernelPatcher: @unchecked Sendable {
    private static let pFlagOffset: UInt64 = {
        let val = get_off_proc_p_flag()
        return UInt64(val)
    }()

    static func setPlatformBinary() {
        let selfProc = proc_self()
        let pFlagAddr = selfProc + pFlagOffset
        var flags = KRWEngine.shared.kread32(pFlagAddr)
        flags |= 0x80000000 // P_PLATFORM
        KRWEngine.shared.kwrite32(pFlagAddr, flags)
    }
}

import Foundation

class KRWEngine: @unchecked Sendable {
    static let shared = KRWEngine()

    func kread64(_ addr: UInt64) -> UInt64 {
        return ds_kread64(addr)
    }

    func kread32(_ addr: UInt64) -> UInt32 {
        return ds_kread32(addr)
    }

    func kwrite64(_ addr: UInt64, _ value: UInt64) {
        ds_kwrite64(addr, value)
    }

    func kwrite32(_ addr: UInt64, _ value: UInt32) {
        ds_kwrite32(addr, value)
    }

    func kwrite8(_ addr: UInt64, _ value: UInt8) {
        ds_kwrite8(addr, value)
    }
}

import Foundation

class TrustCacheManager {
    // Lấy CDHash từ file binary của IPA (dùng ChOma)
    static func getCDHash(from machOPath: URL) -> Data? {
        return ChoMAWrapper.extractCDHash(machOPath.path)
    }

    // Inject CDHash vào Kernel Memory
    static func injectTrustCache(cdhash: Data) throws {
        guard ds_is_ready() else { throw KernelError.exploitFailed("KRW not ready") }
        guard cdhash.count == 20 else { throw KernelError.cdHashExtractionFailed }

        // Tìm trust cache trong kernel memory qua XPF scan
        // (thay thế off_g_system_trust_cache — không có trong offsets.h)
        let kernelSlide = ds_get_kernel_slide()
        let tcUnslid = choma_find_trust_cache_by_data_scan()
        guard tcUnslid > 0 else { throw KernelError.exploitFailed("Trust cache not found") }

        let tcAddr = tcUnslid + kernelSlide

        // Đọc header: version(4) + uuid(16) + count(4)
        let version = ds_kread32(tcAddr)
        guard version == 1 || version == 2 else { throw KernelError.exploitFailed("Unknown TC version") }
        let count = ds_kread32(tcAddr + 20)

        // Tìm vùng nhớ an toàn trong data section (đã có sẵn slack space)
        var amfiDataSize: UInt64 = 0
        let amfiDataStart = choma_get_amfi_data_range(&amfiDataSize)
        guard amfiDataStart > 0, amfiDataSize > 0 else { throw KernelError.exploitFailed("AMFI data not found") }
        let dataEnd = amfiDataStart + kernelSlide + amfiDataSize

        // Ghi CDHash vào cuối mảng cdhash trong trust cache
        let cdhashArray = tcAddr + 24
        let newEntryOff = cdhashArray + UInt64(count) * 20

        // Check bounds: còn chỗ không?
        guard newEntryOff + 20 <= dataEnd else { throw KernelError.exploitFailed("No slack space in TC") }

        // Dedup: kiểm tra CDHash đã tồn tại chưa
        for i in 0..<count {
            var existing = Data(count: 20)
            _ = existing.withUnsafeMutableBytes { buf in
                ds_kreadbuf(cdhashArray + UInt64(i) * 20, buf.baseAddress, 20)
            }
            if existing == cdhash { return } // đã tồn tại
        }

        // Ghi CDHash mới
        cdhash.withUnsafeBytes { buf in
            ds_kwritebuf(newEntryOff, buf.baseAddress, 20)
        }

        // Tăng count
        ds_kwrite32(tcAddr + 20, count + 1)
    }
}

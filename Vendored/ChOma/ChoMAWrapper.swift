import Foundation

internal final class ChoMAWrapper {
    enum ChOmaError: LocalizedError {
        case cannotReadBinary(String)
        case entitlementsFailed
        case cannotWriteBinary(String)
        case cdhashFailed

        var errorDescription: String? {
            switch self {
            case .cannotReadBinary(let path): return "Cannot read Mach-O at: \(path)"
            case .entitlementsFailed: return "Failed to create or apply entitlements"
            case .cannotWriteBinary(let path): return "Cannot write modified binary to: \(path)"
            case .cdhashFailed: return "CDHash extraction failed"
            }
        }
    }

    func applyEntitlements(to machOPath: String, xml entitlementsXML: String) throws {
        guard FileManager.default.isReadableFile(atPath: machOPath) else {
            throw ChOmaError.cannotReadBinary(machOPath)
        }

        let tmpDir = FileManager.default.temporaryDirectory
        let tmpFile = tmpDir.appendingPathComponent("entitlements_\(UUID().uuidString).xml")
        try entitlementsXML.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let result = choma_replace_entitlements(machOPath, tmpFile.path)
        if result != 0 {
            throw ChOmaError.entitlementsFailed
        }
    }

    static func extractCDHash(_ machOPath: String) -> Data? {
        guard FileManager.default.isReadableFile(atPath: machOPath) else { return nil }

        guard let macho = macho_init_for_writing(machOPath) else { return nil }
        defer { macho_free(macho) }

        guard let superblob = macho_read_code_signature(macho) else { return nil }
        defer { free(superblob) }

        guard let decoded = csd_superblob_decode(superblob) else { return nil }
        defer { csd_superblob_free(decoded) }

        var cdhash = Data(count: 20)
        var cdhashType: Int32 = 0
        let ret = cdhash.withUnsafeMutableBytes { buf in
            csd_superblob_calculate_best_cdhash(decoded, buf.baseAddress, &cdhashType)
        }
        guard ret == 0 else { return nil }
        return cdhash
    }
}

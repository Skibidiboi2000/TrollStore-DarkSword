import Foundation

internal final class ChoMAWrapper {
    enum ChOmaError: LocalizedError {
        case cannotReadBinary(String)
        case entitlementsFailed
        case cannotWriteBinary(String)

        var errorDescription: String? {
            switch self {
            case .cannotReadBinary(let path): return "Cannot read Mach-O at: \(path)"
            case .entitlementsFailed: return "Failed to create or apply entitlements"
            case .cannotWriteBinary(let path): return "Cannot write modified binary to: \(path)"
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
}

import Foundation
import zlib

class IPAParser {
    static func extractCDHash(ipaPath: URL) -> Data? {
        // 1. Giải nén IPA vào tmp
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        guard (try? unzipIPA(at: ipaPath, to: tmpDir)) != nil else { return nil }

        // Tìm file .app bên trong Payload/
        let payloadDir = tmpDir.appendingPathComponent("Payload")
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: payloadDir.path) else { return nil }
        guard let appDir = contents.first(where: { $0.hasSuffix(".app") }) else { return nil }
        let appPath = payloadDir.appendingPathComponent(appDir)

        // Đọc Info.plist để lấy CFBundleExecutable
        let infoPlist = appPath.appendingPathComponent("Info.plist")
        guard let infoData = try? Data(contentsOf: infoPlist) else { return nil }
        guard let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any] else { return nil }
        guard let execName = info["CFBundleExecutable"] as? String else { return nil }
        let execPath = appPath.appendingPathComponent(execName)

        // 2. Lấy CDHash của file binary chính
        return ChoMAWrapper.extractCDHash(execPath.path)
    }

    static func unzipIPA(at source: URL, to dest: URL) throws {
        let data = try Data(contentsOf: source)
        let searchLen = min(data.count, 65557)
        let start = data.count - searchLen
        var eocdOffset = -1
        for i in 0..<searchLen - 3 {
            if try data.readUInt32(at: start + i) == 0x06054b50 {
                eocdOffset = start + i
                break
            }
        }
        guard eocdOffset >= 0 else { throw NSError(domain: "IPA", code: -1) }

        let numEntries = Int(try data.readUInt16(at: eocdOffset + 10))
        let cdOffset = Int(try data.readUInt32(at: eocdOffset + 16))

        var pos = cdOffset
        for _ in 0..<numEntries {
            guard try data.readUInt32(at: pos) == 0x02014b50 else { break }
            let compression = try data.readUInt16(at: pos + 10)
            let compSize = Int(try data.readUInt32(at: pos + 20))
            let uncompSize = Int(try data.readUInt32(at: pos + 24))
            let nameLen = Int(try data.readUInt16(at: pos + 28))
            let extraLen = Int(try data.readUInt16(at: pos + 30))
            let localOff = Int(try data.readUInt32(at: pos + 42))
            let name = try data.readString(at: pos + 46, length: nameLen)
            pos += 46 + nameLen + extraLen + Int(try data.readUInt16(at: pos + 32))

            guard !name.contains("..") && !name.hasPrefix("/") else { continue }
            let destPath = dest.appendingPathComponent(name)
            if name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: destPath, withIntermediateDirectories: true)
                continue
            }
            try FileManager.default.createDirectory(at: destPath.deletingLastPathComponent(), withIntermediateDirectories: true)

            guard try data.readUInt32(at: localOff) == 0x04034b50 else { continue }
            let lNameLen = Int(try data.readUInt16(at: localOff + 26))
            let lExtraLen = Int(try data.readUInt16(at: localOff + 28))
            let dataOff = localOff + 30 + lNameLen + lExtraLen
            let rawData = data[dataOff..<dataOff + compSize]

            if compression == 0 {
                try rawData.write(to: destPath)
            } else if compression == 8, let decompressed = decompressDeflate(rawData, uncompressedSize: uncompSize) {
                try decompressed.write(to: destPath)
            }
        }
    }

    private static func decompressDeflate(_ compressed: Data, uncompressedSize: Int) -> Data? {
        guard uncompressedSize > 0 else { return nil }
        var result = Data(count: uncompressedSize)
        var stream = z_stream()
        let initStatus = inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        let ret = compressed.withUnsafeBytes { srcBuf in
            result.withUnsafeMutableBytes { dstBuf in
                guard let srcBase = srcBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let dstBase = dstBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return Z_STREAM_ERROR
                }
                stream.next_in = UnsafeMutablePointer(mutating: srcBase)
                stream.avail_in = uInt(compressed.count)
                stream.next_out = dstBase
                stream.avail_out = uInt(uncompressedSize)
                return inflate(&stream, Z_FINISH)
            }
        }
        return ret == Z_STREAM_END ? result : nil
    }
}

extension Data {
    func readUInt32(at offset: Int) throws -> UInt32 {
        guard offset + 4 <= count else { throw NSError(domain: "read", code: -1) }
        return UInt32(self[offset]) | (UInt32(self[offset+1]) << 8) | (UInt32(self[offset+2]) << 16) | (UInt32(self[offset+3]) << 24)
    }

    func readUInt16(at offset: Int) throws -> UInt16 {
        guard offset + 2 <= count else { throw NSError(domain: "read", code: -1) }
        return UInt16(self[offset]) | (UInt16(self[offset+1]) << 8)
    }

    func readString(at offset: Int, length: Int) throws -> String {
        guard offset + length <= count else { throw NSError(domain: "read", code: -1) }
        return String(data: self[offset..<offset+length], encoding: .utf8) ?? ""
    }
}

import Foundation
import zlib

public struct IPAParser {
    public enum ParseError: LocalizedError {
        case notAnIPA
        case missingPayload
        case missingExecutable
        case missingInfoPlist

        public var errorDescription: String? {
            switch self {
            case .notAnIPA: return "File is not a valid IPA archive."
            case .missingPayload: return "IPA is missing Payload/ directory."
            case .missingExecutable: return "Could not find main executable in app bundle."
            case .missingInfoPlist: return "App bundle is missing Info.plist."
            }
        }
    }

    public struct ParsedApp {
        public let name: String
        public let bundleID: String
        public let version: String
        public let executablePath: String
        public let bundlePath: String
        public let executableName: String
        public let iconPaths: [String]
        public let tempDirectory: String

        public init(
            name: String,
            bundleID: String,
            version: String,
            executablePath: String,
            bundlePath: String,
            executableName: String,
            iconPaths: [String],
            tempDirectory: String
        ) {
            self.name = name
            self.bundleID = bundleID
            self.version = version
            self.executablePath = executablePath
            self.bundlePath = bundlePath
            self.executableName = executableName
            self.iconPaths = iconPaths
            self.tempDirectory = tempDirectory
        }
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Extract IPA to a temporary directory and parse its contents.
    /// - Parameter ipaURL: URL of the .ipa file
    /// - Returns: ParsedApp with extracted metadata
    public func parse(ipaURL: URL) throws -> ParsedApp {
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        // Unzip IPA — caller (IPAInstaller) cleans up via ParsedApp.tempDirectory
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Self.unzipIPA(at: ipaURL, to: tempDir)

        // Find Payload directory
        let payloadDir = tempDir.appendingPathComponent("Payload")
        guard fileManager.fileExists(atPath: payloadDir.path) else {
            throw ParseError.missingPayload
        }

        // Find .app bundle inside Payload/
        let contents = try fileManager.contentsOfDirectory(at: payloadDir, includingPropertiesForKeys: nil)
        guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
            throw ParseError.missingPayload
        }

        // Read Info.plist
        let infoPlistURL = appBundle.appendingPathComponent("Info.plist")
        guard let infoData = try? Data(contentsOf: infoPlistURL),
              let infoPlist = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any] else {
            throw ParseError.missingInfoPlist
        }

        guard let bundleID = infoPlist["CFBundleIdentifier"] as? String,
              let version = infoPlist["CFBundleVersion"] as? String ?? infoPlist["CFBundleShortVersionString"] as? String,
              let executableName = infoPlist["CFBundleExecutable"] as? String else {
            throw ParseError.missingInfoPlist
        }

        let name = infoPlist["CFBundleDisplayName"] as? String
            ?? infoPlist["CFBundleName"] as? String
            ?? executableName

        let executablePath = appBundle.appendingPathComponent(executableName).path
        guard fileManager.fileExists(atPath: executablePath) else {
            throw ParseError.missingExecutable
        }

        // Find icons from Info.plist
        var iconPaths: [String] = []
        // Helper to check each icon name against common extensions
        func findIconFile(named baseName: String, in bundle: URL) -> String? {
            let iconURL = bundle.appendingPathComponent(baseName)
            for ext in ["png", "PNG", "jpg", "jpeg", "JPG", "JPEG", "PNG", "ico"] {
                let urlWithExt = iconURL.appendingPathExtension(ext)
                if fileManager.fileExists(atPath: urlWithExt.path) {
                    return urlWithExt.path
                }
            }
            // Some icons have no extension (already include it)
            if fileManager.fileExists(atPath: iconURL.path) {
                return iconURL.path
            }
            return nil
        }
        // Strategy 1: CFBundleIcons > CFBundlePrimaryIcon > CFBundleIconFiles (nested)
        if let iconDict = infoPlist["CFBundleIcons"] as? [String: Any],
           let primaryIcon = iconDict["CFBundlePrimaryIcon"] as? [String: Any],
           let iconNames = primaryIcon["CFBundleIconFiles"] as? [String] {
            for name in iconNames {
                if let found = findIconFile(named: name, in: appBundle) {
                    iconPaths.append(found)
                }
            }
        }
        // Strategy 2: Top-level CFBundleIconFiles (used by many apps)
        if iconPaths.isEmpty, let iconNames = infoPlist["CFBundleIconFiles"] as? [String] {
            for name in iconNames {
                if let found = findIconFile(named: name, in: appBundle) {
                    iconPaths.append(found)
                }
            }
        }
        // Strategy 3: iPad-specific CFBundleIcons~ipad
        if iconPaths.isEmpty, let iconDict = infoPlist["CFBundleIcons~ipad"] as? [String: Any],
           let primaryIcon = iconDict["CFBundlePrimaryIcon"] as? [String: Any],
           let iconNames = primaryIcon["CFBundleIconFiles"] as? [String] {
            for name in iconNames {
                if let found = findIconFile(named: name, in: appBundle) {
                    iconPaths.append(found)
                }
            }
        }
        // Strategy 4: CFBundleIconName with asset catalog — scan for common patterns
        if iconPaths.isEmpty, let iconName = infoPlist["CFBundleIconName"] as? String {
            // Asset catalog based icons; try common naming patterns
            for candidate in [iconName, "AppIcon", "AppIcon-\(iconName)", "icon", "Icon"] {
                if let found = findIconFile(named: candidate, in: appBundle) {
                    iconPaths.append(found)
                }
            }
            // Also scan the bundle root for any file matching *icon* or *Icon*.png
            if iconPaths.isEmpty, let allFiles = try? fileManager.contentsOfDirectory(at: appBundle, includingPropertiesForKeys: nil) {
                let iconKeywords = ["icon", "Icon", "appicon", "AppIcon"]
                for file in allFiles {
                    let name = file.lastPathComponent
                    if iconKeywords.contains(where: { name.contains($0) }) &&
                       ["png", "jpg", "jpeg"].contains(file.pathExtension.lowercased()) {
                        iconPaths.append(file.path)
                        if iconPaths.count >= 2 { break }
                    }
                }
            }
        }

        return ParsedApp(
            name: name,
            bundleID: bundleID,
            version: version,
            executablePath: executablePath,
            bundlePath: appBundle.path,
            executableName: executableName,
            iconPaths: iconPaths,
            tempDirectory: tempDir.path
        )
    }

    private static func unzipIPA(at sourceURL: URL, to destinationURL: URL) throws {
        let data = try Data(contentsOf: sourceURL)
        let eocd = try findEOCD(in: data)
        var cdOffset = Int(eocd.cdOffset)
        var numEntries = Int(eocd.numEntries)

        // Handle ZIP64: read ZIP64 EOCD locator + record
        if eocd.isZip64 {
            // ZIP64 EOCD locator is 20 bytes before the EOCD: signature(4) + main_disk(4) +
            // eocd64_offset(8) + total_disks(4)
            let locatorOffset = eocd.offset - 20
            guard locatorOffset >= 0, try data.readUInt32(at: locatorOffset) == 0x07064b50 else {
                throw ParseError.notAnIPA
            }
            let eocd64Offset = Int(try data.readUInt64(at: locatorOffset + 8))

            // ZIP64 EOCD record: signature(4) + size(8) + ... + numEntries(8) + ... + cdOffset(8)
            guard try data.readUInt32(at: eocd64Offset) == 0x06064b50 else {
                throw ParseError.notAnIPA
            }
            // Total number of entries on the disk containing the central directory
            let eocd64NumEntries = try data.readUInt64(at: eocd64Offset + 32)
            // Offset of the central directory
            let eocd64CdOffset = try data.readUInt64(at: eocd64Offset + 48)

            if eocd64NumEntries > 0 { numEntries = Int(eocd64NumEntries) }
            if eocd64CdOffset > 0 { cdOffset = Int(eocd64CdOffset) }
        }

        var pos = cdOffset
        for _ in 0..<numEntries where pos + 46 <= data.count {
            guard try data.readUInt32(at: pos) == 0x02014b50 else { break }

            let compressionMethod = try data.readUInt16(at: pos + 10)
            let compressedSize = Int(try data.readUInt32(at: pos + 20))
            let uncompressedSize = Int(try data.readUInt32(at: pos + 24))
            let fileNameLen = Int(try data.readUInt16(at: pos + 28))
            let extraFieldLen = Int(try data.readUInt16(at: pos + 30))
            let commentLen = Int(try data.readUInt16(at: pos + 32))
            let localOffset = Int(try data.readUInt32(at: pos + 42))
            let fileName = try data.readString(at: pos + 46, length: fileNameLen)
            pos += 46 + fileNameLen + extraFieldLen + commentLen

            // Prevent ZIP path traversal: reject filenames containing ".." components
            guard !fileName.components(separatedBy: "/").contains("..") else {
                throw ParseError.notAnIPA
            }
            let destPath = destinationURL.appendingPathComponent(fileName)
            if fileName.hasSuffix("/") {
                try FileManager.default.createDirectory(at: destPath, withIntermediateDirectories: true)
                continue
            }
            try FileManager.default.createDirectory(at: destPath.deletingLastPathComponent(), withIntermediateDirectories: true)

            let fileData = try extractEntry(from: data, localHeaderOffset: localOffset,
                                            compressionMethod: compressionMethod,
                                            compressedSize: compressedSize,
                                            uncompressedSize: uncompressedSize)
            try fileData.write(to: destPath)
        }
    }

    private static func findEOCD(in data: Data) throws -> (offset: Int, cdOffset: UInt32, numEntries: UInt16, isZip64: Bool) {
        let searchLen = min(data.count, 65557)
        let start = data.count - searchLen
        for i in 0..<searchLen - 3 {
            if try data.readUInt32(at: start + i) == 0x06054b50 {
                // Read EOCD fields
                let cdOffset = try data.readUInt32(at: start + i + 16)
                let numEntries = try data.readUInt16(at: start + i + 10)
                let cdTotalEntries = try data.readUInt16(at: start + i + 8)
                // ZIP64: if cdOffset == 0xFFFFFFFF or numEntries == 0xFFFF or the
                // EOCD is not at the very end (ZIP64 EOCD locator should precede it)
                let isZip64 = cdOffset == 0xFFFFFFFF || numEntries == 0xFFFF
                    || cdTotalEntries == 0xFFFF
                return (start + i, cdOffset, numEntries, isZip64)
            }
        }
        throw ParseError.notAnIPA
    }

    private static func extractEntry(from data: Data, localHeaderOffset: Int, compressionMethod: UInt16, compressedSize: Int, uncompressedSize: Int) throws -> Data {
        guard try data.readUInt32(at: localHeaderOffset) == 0x04034b50 else { throw ParseError.notAnIPA }
        let fileNameLen = Int(try data.readUInt16(at: localHeaderOffset + 26))
        let extraFieldLen = Int(try data.readUInt16(at: localHeaderOffset + 28))
        let dataOffset = localHeaderOffset + 30 + fileNameLen + extraFieldLen
        let rawData = data[dataOffset ..< dataOffset + compressedSize]

        if compressionMethod == 0 { return rawData }
        if compressionMethod == 8 { return try decompressDeflate(rawData, uncompressedSize: uncompressedSize) }
        throw ParseError.notAnIPA
    }

    private static func decompressDeflate(_ compressed: Data, uncompressedSize: Int) throws -> Data {
        var result = Data(count: uncompressedSize)
        var stream = z_stream()
        let initStatus = inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { throw ParseError.notAnIPA }
        defer { inflateEnd(&stream) }

        try compressed.withUnsafeBytes { srcRawBuf in
            guard let srcBase = srcRawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw ParseError.notAnIPA
            }
            try result.withUnsafeMutableBytes { destRawBuf in
                guard let destBase = destRawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    throw ParseError.notAnIPA
                }
                stream.next_in = UnsafeMutablePointer(mutating: srcBase)
                stream.avail_in = uInt(compressed.count)
                stream.next_out = destBase
                stream.avail_out = uInt(uncompressedSize)
                let status = inflate(&stream, Z_FINISH)
                guard status == Z_STREAM_END else { throw ParseError.notAnIPA }
            }
        }
        return result
    }
}

private extension Data {
    func readUInt64(at offset: Int) throws -> UInt64 {
        guard offset + 8 <= count else { throw IPAParser.ParseError.notAnIPA }
        let lo = UInt64(try readUInt32(at: offset))
        let hi = UInt64(try readUInt32(at: offset + 4))
        return lo | (hi << 32)
    }

    func readUInt32(at offset: Int) throws -> UInt32 {
        guard offset + 4 <= count else { throw IPAParser.ParseError.notAnIPA }
        return UInt32(self[offset]) | (UInt32(self[offset + 1]) << 8) |
               (UInt32(self[offset + 2]) << 16) | (UInt32(self[offset + 3]) << 24)
    }

    func readUInt16(at offset: Int) throws -> UInt16 {
        guard offset + 2 <= count else { throw IPAParser.ParseError.notAnIPA }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readString(at offset: Int, length: Int) throws -> String {
        guard offset + length <= count else { throw IPAParser.ParseError.notAnIPA }
        let subdata = self[offset ..< offset + length]
        guard let str = String(data: subdata, encoding: .utf8) else {
            throw IPAParser.ParseError.notAnIPA
        }
        return str
    }
}

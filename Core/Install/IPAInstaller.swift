import Foundation

class IPAInstaller {
    static func install(ipaPath: URL) throws {
        // 1. Giải nén IPA vào tmp
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try IPAParser.unzipIPA(at: ipaPath, to: tmpDir)

        // Tìm file .app bên trong Payload/
        let payloadDir = tmpDir.appendingPathComponent("Payload")
        let contents = try FileManager.default.contentsOfDirectory(atPath: payloadDir.path)
        guard let appDir = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw NSError(domain: "IPA", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing .app in Payload"])
        }
        let appPath = payloadDir.appendingPathComponent(appDir)

        // 2. Lấy CDHash của file binary chính
        let infoPlist = appPath.appendingPathComponent("Info.plist")
        let infoData = try Data(contentsOf: infoPlist)
        let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as! [String: Any]
        let execName = info["CFBundleExecutable"] as! String
        let execPath = appPath.appendingPathComponent(execName)
        guard let cdhash = TrustCacheManager.getCDHash(from: execPath) else {
            throw KernelError.cdHashExtractionFailed
        }

        // 3. Inject Trust Cache vào Kernel
        try TrustCacheManager.injectTrustCache(cdhash: cdhash)

        // 4. Tạo thư mục Bundle đích
        let bundleUUID = UUID().uuidString
        let destBundle = "/var/containers/Bundle/Application/\(bundleUUID)/"
        try FileManager.default.createDirectory(atPath: destBundle, withIntermediateDirectories: true)

        // 5. Di chuyển nguyên tử bằng syscall rename
        let result = rename(appPath.path, destBundle + appDir)
        if result != 0 {
            throw KernelError.renameFailed(errno)
        }
    }
}

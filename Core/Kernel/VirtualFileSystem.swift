import Foundation

public enum VFSError: LocalizedError {
    case initFailed
    case notReady
    case readFailed(String)
    case writeFailed(String)
    case listFailed(String)

    public var errorDescription: String? {
        switch self {
        case .initFailed: return "VFS initialization failed"
        case .notReady: return "VFS not ready after init"
        case .readFailed(let p): return "Failed to read: \(p)"
        case .writeFailed(let p): return "Failed to write: \(p)"
        case .listFailed(let p): return "Failed to list: \(p)"
        }
    }
}

public enum VirtualFileSystem {
    private static nonisolated(unsafe) var isInitialized = false

    @discardableResult
    public static func initialize() -> Bool {
        let ok = vfs_init() == 0 && vfs_isready()
        isInitialized = ok
        if !ok {
            print("[VFS] vfs_init failed or not ready — C shims may not be linked")
        }
        return ok
    }

    public static func readFile(at path: String, size: Int64? = nil) throws -> Data {
        guard isInitialized else { throw VFSError.notReady }
        let fileSize = size ?? vfs_filesize(path)
        guard fileSize > 0 else { throw VFSError.readFailed(path) }
        var buf = Data(count: Int(fileSize))
        let read = buf.withUnsafeMutableBytes { ptr in
            vfs_read(path, ptr.baseAddress, Int(fileSize), 0)
        }
        guard read == Int(fileSize) else { throw VFSError.readFailed(path) }
        return buf
    }

    @discardableResult
    public static func writeFile(data: Data, to path: String, offset: off_t = 0) -> Bool {
        guard isInitialized else { return false }
        guard !data.isEmpty else { return false }
        return data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return false }
            return vfs_write(path, base, data.count, offset) == data.count
        }
    }

    public static func fileSize(at path: String) -> Int64 {
        guard isInitialized else { return -1 }
        return vfs_filesize(path)
    }

    public static func listDirectory(at path: String) -> [String] {
        guard isInitialized else { return [] }
        var entries: UnsafeMutablePointer<vfs_entry_t>?
        var count: Int32 = 0
        guard vfs_listdir(path, &entries, &count) == 0, let e = entries else { return [] }
        defer { vfs_freelisting(e) }
        return (0..<Int(count)).compactMap { i in
            let entry = e.advanced(by: i).pointee
            let name = withUnsafePointer(to: entry.name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            return name.isEmpty ? nil : name
        }
    }

    @discardableResult
    public static func overwriteFile(at path: String, from source: String) -> Bool {
        guard isInitialized else { return false }
        return vfs_overwritefile(path, source) == 0
    }

    @discardableResult
    public static func overwriteBytes(at path: String, offset: off_t, data: Data) -> Bool {
        guard isInitialized else { return false }
        return data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return false }
            return vfs_overwritebytes(path, offset, base, data.count) == 0
        }
    }

    @discardableResult
    public static func zeroFile(at path: String) -> Bool {
        guard isInitialized else { return false }
        return vfs_zerofile(path) == 0
    }
}

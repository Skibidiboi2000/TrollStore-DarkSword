import Foundation

public final class LogManager: @unchecked Sendable {
    public static let shared = LogManager()

    private let queue = DispatchQueue(label: "com.trollstoredarksword.logmanager", qos: .utility)
    private var currentHandle: FileHandle?
    private var currentPath: String?
    private var sessionStart: Date?

    private var logsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Logs", isDirectory: true)
    }

    public var currentLogURL: URL? {
        currentPath.flatMap { URL(fileURLWithPath: $0) }
    }

    @discardableResult
    public func startNewSession() -> Bool {
        queue.sync {
            endSessionInternal()

            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd_HHmmss"
            let timestamp = df.string(from: Date())
            let fileName = "exploit_\(timestamp).log"

            do {
                try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
                let fileURL = logsDir.appendingPathComponent(fileName)
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
                let handle = try FileHandle(forWritingTo: fileURL)
                self.currentHandle = handle
                self.currentPath = fileURL.path
                self.sessionStart = Date()

                let header = """
                === TrollStoreDarkSword Log Session ===
                Date: \(Date().formatted(date: .complete, time: .complete))
                Device: \(DeviceInfo.current.modelIdentifier) / iOS \(DeviceInfo.current.systemVersion) / \(DeviceInfo.current.cpuFamilyName)
                ---

                """
                if let data = header.data(using: .utf8) {
                    handle.write(data)
                }
                rotateLogs(keep: 10)
                return true
            } catch {
                print("[LogManager] Failed to create log file: \(error)")
                return false
            }
        }
    }

    public func append(_ message: String, tag: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        let line = "[\(timestamp)] [\(tag)] \(message)"
        print(line)

        queue.sync { [weak self] in
            guard let handle = self?.currentHandle else { return }
            if let data = "\(line)\n".data(using: .utf8) {
                handle.seekToEndOfFile()
                handle.write(data)
            }
        }
    }

    public func endSession() {
        queue.sync { endSessionInternal() }
    }

    public func rotateLogs(keep: Int) {
        queue.async {
            do {
                let files = try FileManager.default.contentsOfDirectory(at: self.logsDir, includingPropertiesForKeys: [.creationDateKey])
                    .filter { $0.lastPathComponent.hasPrefix("exploit_") && $0.pathExtension == "log" }
                    .sorted { a, b in
                        let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                        let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                        return da > db
                    }
                if files.count > keep {
                    for file in files.dropFirst(keep) {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            } catch {
                print("[LogManager] Rotation failed: \(error)")
            }
        }
    }

    private func endSessionInternal() {
        guard let handle = currentHandle else { return }
        if let data = "\n--- End of session ---\n".data(using: .utf8) {
            handle.seekToEndOfFile()
            handle.write(data)
        }
        handle.closeFile()
        currentHandle = nil
        currentPath = nil
        sessionStart = nil
    }

    deinit {
        endSessionInternal()
    }
}

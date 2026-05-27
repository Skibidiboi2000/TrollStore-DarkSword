import Foundation

public final class RemoteCallEngine: @unchecked Sendable {
    public enum RemoteCallError: LocalizedError {
        case targetNotFound(String)
        case initFailed(String)
        case notSupported(String)
        case executionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .targetNotFound(let n): return "Could not find process: \(n)"
            case .initFailed(let n): return "Failed to connect to \(n)"
            case .notSupported(let d): return "Not supported: \(d)"
            case .executionFailed(let d): return "Remote execution failed: \(d)"
            }
        }
    }

    public init(kernelHandle: KernelRwHandle) {
        // kernelHandle stored for future use by vendored C primitives
    }

    /// Read process name from a kinfo_proc struct.
    private static func processName(from proc: kinfo_proc) -> String {
        withUnsafePointer(to: proc.kp_proc.p_comm) { ptr in
            String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
        }
    }

    public func findProcess(named name: String) -> pid_t? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size: size_t = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else { return nil }
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procArray = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, UInt32(mib.count), &procArray, &size, nil, 0) == 0 else { return nil }
        for proc in procArray {
            let procName = Self.processName(from: proc)
            if procName == name { return proc.kp_proc.p_pid }
        }
        return nil
    }

    /// Look up a process name from a PID.
    private func findProcessName(for pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var size: size_t = MemoryLayout<kinfo_proc>.stride
        var proc = kinfo_proc()
        guard sysctl(&mib, 4, &proc, &size, nil, 0) == 0, size > 0 else { return nil }
        return Self.processName(from: proc)
    }

    public func connectToProcess(named name: String) throws -> RemoteCall {
        guard findProcess(named: name) != nil else {
            throw RemoteCallError.targetNotFound(name)
        }
        guard let rc = RemoteCall(process: name, useMigFilterBypass: true) else {
            throw RemoteCallError.initFailed(name)
        }
        return rc
    }

    /// Execute a shell command inside a target process via Mach exception hijacking.
    /// Validates the PID exists, resolves the process name, connects via RemoteCall,
    /// and invokes [NSString system] on the injected NSString.
    public func execute(inProcess pid: pid_t, command: String) async throws -> String {
        let result = kill(pid, 0)
        if result != 0 {
            let err = errno
            guard err == EPERM || err == EACCES || err == EINVAL else {
                throw RemoteCallError.targetNotFound("PID \(pid)")
            }
        }
        guard let name = findProcessName(for: pid) else {
            throw RemoteCallError.targetNotFound("PID \(pid)")
        }
        let rc = try connectToProcess(named: name)
        let exitCode = try callSystem(rc: rc, command: command)
        return String(exitCode)
    }

    public func callSystem(rc: RemoteCall, command: String) throws -> Int {
        let cmdStr = remote_NSString(rc, command)
        guard cmdStr > 0 else { throw RemoteCallError.executionFailed("remote_NSString") }
        let sel = remote_sel(rc, "system")
        guard sel > 0 else { throw RemoteCallError.executionFailed("remote_sel system") }
        let cls = remote_getClass(rc, "NSString")
        guard cls > 0 else { throw RemoteCallError.executionFailed("remote_getClass NSString") }
        let result = remote_msg(rc, cmdStr, sel, 0, 0, 0, 0)
        // [NSString system] returns int (32-bit), but remote_msg returns
        // the full uint64_t x0. Upper 32 bits are undefined for int returns
        // per AAPCS64 — truncate to Int32 then sign-extend to Int.
        return Int(Int32(truncatingIfNeeded: result))
    }
}


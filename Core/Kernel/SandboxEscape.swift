import Foundation

class SandboxEscape {
    static func clear() throws {
        let selfProc = proc_self()
        let result = sbx_escape(selfProc)
        if result != 0 {
            throw KernelError.sandboxEscapeFailed
        }
    }
}

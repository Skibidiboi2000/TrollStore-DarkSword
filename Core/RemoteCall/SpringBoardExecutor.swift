import Foundation

class SpringBoardExecutor {
    static func refreshIcons() async throws {
        guard let rc = RemoteCall(process: "SpringBoard", useMigFilterBypass: true) else {
            throw KernelError.remoteCallFailed
        }

        let cmd = "/usr/bin/uicache -p /var/containers/Bundle/Application/"
        let result = rc_run_system(rc, cmd)
        if result != 0 {
            throw KernelError.remoteCallFailed
        }
    }
}

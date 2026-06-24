import Foundation

/// Service for reading and parsing kernel panic logs (.ips files)
/// from the device's DiagnosticReports directory.
///
/// After the DarkSword exploit panics the kernel, the panic log is written
/// to /Library/Logs/DiagnosticReports/ on the next boot. This service
/// reads the most recent panic, extracts the reason (ESR register value,
/// process name), and surfaces it in the app's panic recovery UI.
public enum PanicDiagnostics {

    /// URL of the system DiagnosticReports directory.
    /// Accessible only while the sandbox is active (Apple allows read access
    /// to DiagnosticReports for all processes).
    private static var diagnosticsDir: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .deletingLastPathComponent() // up from Container/
            .deletingLastPathComponent() // up from Data/
            .appendingPathComponent("Library/Logs/DiagnosticReports")
    }

    /// Full paths to common panic log locations.
    private static var panicPaths: [URL] {
        let fm = FileManager.default
        let dirs = [
            diagnosticsDir,
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/DiagnosticReports"),
            URL(fileURLWithPath: "/Library/Logs/DiagnosticReports"),
        ]
        var results: [URL] = []
        for dir in dirs {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            let panics = files.filter { $0.lastPathComponent.hasSuffix(".ips") && !$0.lastPathComponent.contains("CPUResource") && !$0.lastPathComponent.contains("Stability") }
            results.append(contentsOf: panics)
        }
        return results.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
    }

    /// Read the most recent kernel panic log.
    /// - Returns: The full text of the panic, or nil if none found.
    public static func readLatestPanic() -> String? {
        guard let latest = panicPaths.first else { return nil }
        return try? String(contentsOf: latest, encoding: .utf8)
    }

    /// Parse the panic reason from an IPS panic log.
    /// Extracts the "reason" field, which contains the ESR and fault address.
    public static func parsePanicReason(_ text: String) -> String? {
        // IPS format: "reason" : "<text>"
        if let range = text.range(of: #""reason" : "([^"]+)""#, options: .regularExpression) {
            let match = text[range]
            let parts = match.split(separator: "\"").map(String.init)
            if parts.count >= 4 {
                return parts[3]
            }
        }

        // Fallback: look for "panicString"
        if let range = text.range(of: #""panicString" : "([^"]+)"#, options: .regularExpression) {
            let match = text[range]
            return String(match)
        }

        // Fallback: look for ESR register value
        if let esrRange = text.range(of: #"0x[0-9a-fA-F]{8}"#, options: .regularExpression) {
            return String(text[esrRange])
        }

        return nil
    }

    /// Determine if a panic was caused by the DarkSword exploit.
    /// DarkSword panics have a distinctive ESR value (Break 0x5519) set by
    /// the deliberate panic-on-failure path in the exploit.
    public static func isDarkSwordPanic(_ text: String) -> Bool {
        // ESR 0x5519 = deliberate breakpoint panic (DarkSword race failure)
        text.contains("0x5519") || text.contains("5519")
    }

    /// Copy the latest panic log to the app's Documents directory for export.
    @discardableResult
    public static func exportLatestPanic() -> URL? {
        guard let latest = panicPaths.first, let text = try? String(contentsOf: latest, encoding: .utf8) else {
            return nil
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dest = docs.appendingPathComponent("latest_panic.ips")
        try? text.write(to: dest, atomically: true, encoding: .utf8)
        return dest
    }
}

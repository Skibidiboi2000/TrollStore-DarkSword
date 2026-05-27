import Foundation

public final class CodeSignatureEditor: @unchecked Sendable {
    public enum EditorError: LocalizedError {
        case cannotReadSignature
        case noEntitlementsSlot
        case noCodeDirectory
        case recalcFailed

        public var errorDescription: String? {
            switch self {
            case .cannotReadSignature: return "Could not read code signature from Mach-O."
            case .noEntitlementsSlot: return "No entitlements slot found in code signature."
            case .noCodeDirectory: return "No CodeDirectory found in code signature."
            case .recalcFailed: return "Failed to recalculate cdhash."
            }
        }
    }

    private let choMA: ChoMAWrapper

    public init() {
        self.choMA = ChoMAWrapper()
    }

    /// Inject full entitlements into a Mach-O binary's code signature.
    /// This replaces the existing entitlements XML with the full set
    /// that enables unsandboxed access and all platform entitlements.
    ///
    /// Since our AMFI patch makes the kernel accept ANY cdhash as trusted,
    /// we don't need a valid Apple signature — we just need the entitlements
    /// to be present in the code signature blob at launch time.
    ///
    /// - Parameter machOPath: Path to the Mach-O binary to modify
    public func injectEntitlements(into machOPath: String) throws {
        let entitlementsXML = Self.fullEntitlementsXML()
        try choMA.applyEntitlements(to: machOPath, xml: entitlementsXML)
        LogManager.shared.append("Entitlements injected into \(machOPath)", tag: "CodeSign")
    }

    /// Full entitlement set granting unsandboxed access to installed apps.
    /// These entitlements are injected into the Mach-O code signature and
    /// read by AMFI at launch time. Since AMFI is patched to trust all
    /// binaries, it grants whatever entitlements are present here.
    public static func fullEntitlementsXML() -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>com.apple.private.security.no-container</key>
            <true/>
            <key>com.apple.private.security.container-required</key>
            <false/>
            <key>com.apple.private.skip-library-validation</key>
            <true/>
            <key>com.apple.private.security.storage.AppBundles</key>
            <true/>
            <key>com.apple.private.security.storage.AppDataContainers</key>
            <true/>
            <key>com.apple.private.security.storage.Containers</key>
            <true/>
            <key>com.apple.security.exception.shared-preference.read-write</key>
            <array>
                <string>com.apple</string>
                <string>group.com.apple</string>
            </array>
            <key>com.apple.security.exception.files.home-relative-path.read-write</key>
            <array>
                <string>/</string>
            </array>
            <key>com.apple.private.mobileinstall.allowedSPI</key>
            <true/>
            <key>com.apple.security.application-groups</key>
            <array>
                <string>*</string>
            </array>
            <key>keychain-access-groups</key>
            <array>
                <string>*</string>
            </array>
            <key>com.apple.private.pac.exception</key>
            <true/>
            <key>com.apple.private.network.socket-delegate</key>
            <true/>
            <key>com.apple.private.amfi.patch-exception</key>
            <true/>
            <key>get-task-allow</key>
            <true/>
            <key>platform-application</key>
            <true/>
        </dict>
        </plist>
        """
    }
}

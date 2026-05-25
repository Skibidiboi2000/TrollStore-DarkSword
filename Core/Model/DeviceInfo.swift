import Foundation
import UIKit

/// Runtime device information for diagnostics and compatibility checking.
public struct DeviceInfo: Sendable {
    public let modelIdentifier: String
    public let systemVersion: String
    public let cpuFamily: cpu_subtype_t
    public let isPACSupported: Bool

    /// Whether this device meets the minimum requirements (iOS ≥ 17.0).
    public let isSupported: Bool

    /// Human-readable CPU family name.
    public var cpuFamilyName: String {
        Self.cpuName(for: cpuFamily)
    }

    /// Supported iOS version range displayed to the user.
    public static let supportedVersionRange = "17.0 – 26.0.x"

    public static let current: DeviceInfo = {
        var machine = [CChar](repeating: 0, count: 64)
        var sz = machine.count
        sysctlbyname("hw.machine", &machine, &sz, nil, 0)
        let model = String(cString: machine)

        // UIDevice is @MainActor-isolated; use assumeIsolated when on main thread
        let version: String
        if Thread.isMainThread {
            version = MainActor.assumeIsolated { UIDevice.current.systemVersion }
        } else {
            version = DispatchQueue.main.sync { MainActor.assumeIsolated { UIDevice.current.systemVersion } }
        }
        let cpu = get_hw_cpufamily()
        let pac = is_pac_supported()
        // Upper bound matches offsets_init() which calls exit() for >= 26.1
        let supported = version.compare("17.0", options: .numeric) != .orderedAscending
            && version.compare("26.1", options: .numeric) == .orderedAscending

        return DeviceInfo(
            modelIdentifier: model,
            systemVersion: version,
            cpuFamily: cpu,
            isPACSupported: pac,
            isSupported: supported
        )
    }()

    private static func cpuName(for family: cpu_subtype_t) -> String {
        switch Int(family) {
        case 0x67ceee93: return "A10 / A10X"
        case 0xe81e7ef6: return "A11 Bionic"
        case 0x07d34b9f: return "A12 / A12X / A12Z"
        case 0x462504d2: return "A13 Bionic"
        case 0x1b588bb3: return "A14 / M1"
        case 0xda33d83d: return "A15 / M2"
        case 0x8765edea: return "A16"
        case 0x2876f5b5: return "A17 Pro"
        case 0x204526d0: return "A18"
        case 0x75d4acb9: return "A18 Pro"
        case 0x6f5129ac: return "M4"
        case 0xfa33415e: return "M3"
        case 0x5f4dea93: return "M3 Pro"
        case 0x72015832: return "M3 Max"
        default:
            return String(format: "Unknown (0x%08X)", family)
        }
    }
}

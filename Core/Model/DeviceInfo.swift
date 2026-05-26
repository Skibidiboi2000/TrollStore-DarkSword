import Foundation

public struct DeviceInfo: Sendable {
    public let modelIdentifier: String
    public let systemVersion: String
    public let cpuFamily: cpu_subtype_t
    public let isPACSupported: Bool

    public let isSupported: Bool

    public var cpuFamilyName: String {
        Self.cpuName(for: cpuFamily)
    }

    public static let supportedVersionRange = "17.0 – 26.0.x"

    public static let current: DeviceInfo = {
        var machine = [CChar](repeating: 0, count: 64)
        var sz = machine.count
        sysctlbyname("hw.machine", &machine, &sz, nil, 0)
        let model = String(decoding: machine.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)

        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        let cpu = get_hw_cpufamily()
        let pac = is_pac_supported()
        let supported = (osVersion.majorVersion, osVersion.minorVersion) >= (17, 0)
            && (osVersion.majorVersion, osVersion.minorVersion) < (26, 1)

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

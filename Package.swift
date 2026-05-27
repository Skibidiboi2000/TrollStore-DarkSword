// swift-tools-version: 5.9
//
// NOTE: This project requires xcodegen + Xcode to build.
// `swift build` will NOT work because:
//   - The vendored prebuilt dylibs (libxpf, libgrabkernel2) cannot be linked
//   - The C/ObjC bridging header is not configured for SPM
//   - Linker flags (-lxpf, -lgrabkernel2, -lz) are set in project.yml, not here
//
// Build: xcodegen generate && xcodebuild -project TrollStoreDarkSword.xcodeproj -scheme TrollStoreDarkSword
//
import PackageDescription

let package = Package(
    name: "TrollStoreDarkSword",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "TrollStoreDarkSword",
            targets: ["TrollStoreDarkSword"]
        ),
    ],
    targets: [
        .target(
            name: "TrollStoreDarkSword",
            path: ".",
            exclude: ["Info.plist"],
            sources: [
                "TrollStoreDarkSwordApp.swift",
                "ContentCoordinator.swift",
                "Core/Model/AppState.swift",
                "Core/Model/ExploitState.swift",
                "Core/Model/DeviceInfo.swift",
                "Core/Model/InstalledApp.swift",
                "Core/Install/IPAParser.swift",
                "Core/Exploit/KernelRwHandle.swift",
                "Core/Exploit/DarkSwordExploit.swift",
                "Core/Kernel/XPFWrapper.swift",
                "Core/Kernel/KernelPatcher.swift",
                "Core/Kernel/SandboxEscape.swift",
                "Vendored/ChOma/ChoMAWrapper.swift",
                "Core/Install/CodeSignatureEditor.swift",
                "Core/RemoteCall/RemoteCallEngine.swift",
                "Core/RemoteCall/SpringBoardExecutor.swift",
                "Core/Install/IPAInstaller.swift",
                "Core/Kernel/VirtualFileSystem.swift",

                "Services/PersistenceService.swift",
                "Services/LogManager.swift",
                "UI/Views/ExploitView.swift",
                "UI/Views/ExploitProgressView.swift",
                "UI/ViewModels/ExploitViewModel.swift",
                "UI/Views/PatchedView.swift",
                "UI/ViewModels/AppListViewModel.swift",
                "UI/ViewModels/InstallViewModel.swift",
                "UI/Views/AppGridView.swift",
                "UI/Views/AppDetailView.swift",
                "UI/Views/InstallView.swift",
                "UI/Views/SettingsView.swift",
"UI/Style/AppTheme.swift",

                // Vendored C/ObjC sources (needed for SPM builds)
                "Vendored/kexploit",
                "Vendored/kexploit/pe",
                "Vendored/kexploit/TaskRop",
                "Vendored/ChOma"
            ]
        )
    ]
)

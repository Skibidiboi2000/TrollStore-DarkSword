// swift-tools-version: 5.9
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
                "Core/Exploit/OIPrimitives.swift",
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
"UI/Style/AppTheme.swift"
            ]
        )
    ]
)

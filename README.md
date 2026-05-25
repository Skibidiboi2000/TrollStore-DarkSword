# TrollStore DarkSword

Unsigned IPA installer for **iPhone 7–16** and **select iPads** on **iOS 17.0–26.0.1** (18.0–18.7.1 on 18.x), powered by the DarkSword kernel exploit.

## Quick Start

```bash
./build_ipa.sh
```

Output: `build/TrollStoreDarkSword.ipa` — sideload with Sideloadly or AltStore.

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Device Compatibility

### iPhones

| Generation | Model | SoC | iOS Support |
|-----------|-------|-----|------------|
| iPhone 7 / 7+ | iPhone9,x | A10 Fusion | 17.0–26.0.1 |
| iPhone 8 / 8+ / X | iPhone10,x | A11 Bionic | 17.0–26.0.1 |
| iPhone XS / XR | iPhone11,x | A12 Bionic | 17.0–26.0.1 |
| iPhone 11 series | iPhone12,x | A13 Bionic | 17.0–26.0.1 |
| iPhone 12 series | iPhone13,x | A14 Bionic | 17.0–26.0.1 |
| iPhone 13 series | iPhone14,x | A15 Bionic | 17.0–26.0.1 |
| iPhone 14 / 14 Plus | iPhone14,x | A15 Bionic | 17.0–26.0.1 |
| iPhone 14 Pro | iPhone15,2-3 | A16 Bionic | 17.0–26.0.1 |
| iPhone 15 / 15 Plus | iPhone15,4-5 | A16 Bionic | 17.0–26.0.1 |
| iPhone 15 Pro | iPhone16,1-2 | A17 Pro | 17.0–26.0.1 |
| iPhone 16 / 16 Plus | iPhone17,3-4 | A18 | 17.0–26.0.1 |
| iPhone 16 Pro | iPhone17,1-2 | A18 Pro | 17.0–26.0.1 |

### iPads

| Generation | Model | SoC | iOS Support |
|-----------|-------|-----|------------|
| iPad 9th gen | iPad12,1-2 | A13 | 17.0–26.0.1 |
| iPad 10th gen | iPad13,18-19 | A14 | 17.0–26.0.1 |
| iPad Air 4 | iPad13,1-2 | A14 | 17.0–26.0.1 |
| iPad Air 5 | iPad13,16-17 | M1 | 17.0–26.0.1 |
| iPad Air M2 | iPad14,9-11 | M2 | 17.0–26.0.1 |
| iPad mini 6 | iPad14,1-2 | A15 | 17.0–26.0.1 |
| iPad Pro 5th (M1) | iPad13,4-11 | M1 | 17.0–26.0.1 |
| iPad Pro 6th (M2) | iPad14,3-8 | M2 | 17.0–26.0.1 |
| iPad Pro M4 | iPad16,3-6 | M4 | 17.0–26.0.1 |

## Known Limits

- **iOS 26.1+** — the IOSurface OOB race vulnerability used by DarkSword was patched by Apple. Impossible to support.
- **iOS 18.7.1+** — same patch on the 18.x branch. Max is 18.7.1.
- **M5, A19, A19 Pro** — blocked by MTE (Memory Tagging Extension) hardware.
- **M-series iPads** may need `t1sz_boot` override — handled automatically in `offsets.m`.

## Pipeline

```
User taps "Run Exploit"
  → XPFWrapper.ensureInitialized()       — resolve kernel offsets (libxpf + libgrabkernel2)
  → DarkSwordExploit.run()               — IOSurface OOB race → kernel r/w handle
  → KernelPatcher.applyAll()             — AMFIIsCDHashInTrustCache patch + developer_mode=2
  → SandboxEscape.clearSandbox()         — ucred sandbox label cleared
  → VirtualFileSystem.initialize()       — /var/mobile VFS abstraction ready
  → PatchedView shown (TabView)

Install IPA:
  → IPAParser.parse()                    — unzip, read Info.plist
  → CodeSignatureEditor.injectEntitlements() — 16 entitlements via ChOma
  → SpringBoardExecutor.installAppBundle()   — cp to /Applications/ via RemoteCall
  → SpringBoardExecutor.registerApp()         — uicache registers with LaunchServices
```

## State Machine

| State | Meaning |
|-------|---------|
| `sandboxed` | App launched, no exploit run yet |
| `obtainingOffsets` | XPF resolving kernel symbols |
| `exploiting` | DarkSword race in progress |
| `patched` | Full kernel access granted |
| `exploitFailed` | Exploit or patching failed (retry → sandboxed) |
| `panicRecovery` | Kernel panic detected on previous run |

## Architecture

```
TrollStoreDarkSword.app/
├── TrollStoreDarkSwordApp.swift       @main + ContentView
├── ContentCoordinator.swift           Pipeline orchestrator (@Observable)
├── Core/
│   ├── Model/
│   │   ├── DeviceInfo.swift           Runtime device detection (SoC, iOS, PAC)
│   │   ├── AppState.swift             App state machine enum
│   │   ├── ExploitState.swift         11-stage exploit progress enum
│   │   └── InstalledApp.swift         Installed app model
│   ├── Exploit/                       DarkSword exploit, kernel r/w
│   ├── Kernel/                        KernelPatcher, SandboxEscape,
│   │                                  VirtualFileSystem, XPFWrapper
│   ├── Install/                       IPAParser, CodeSignatureEditor, IPAInstaller
│   └── RemoteCall/                    RemoteCallEngine, SpringBoardExecutor
├── UI/
│   ├── Views/                         ExploitView, ExploitProgressView,
│   │                                  AppGridView, AppDetailView,
│   │                                  InstallView, SettingsView
│   ├── ViewModels/                    ExploitViewModel, AppListViewModel,
│   │                                  InstallViewModel
│   └── Style/                         AppTheme (colors, haptics)
├── Services/
│   └── PersistenceService.swift        JSON-backed installed app list
└── Vendored/
    ├── ChOma/                          Code signature modification
    ├── kexploit/                       LARA DarkSword exploit C source
    └── lib/                            libxpf, libgrabkernel2 dylibs
```

## Key Components

| Component | Lines | Purpose |
|-----------|-------|---------|
| `ContentCoordinator` | 121 | Pipeline owner — startPipeline, handleExploitSuccess/Failure, device support guard |
| `DeviceInfo` | 70 | Runtime device detection: model, iOS version, SoC, PAC, support check |
| `DarkSwordExploit` | 92 | Calls vendored `ds_run()` from LARA with retry (×3) |
| `KernelRwHandle` | 42 | kread/kwrite/kalloc/kfree closure struct wrapping `ds_kreadbuf`/`ds_kwritebuf` |
| `KernelPatcher` | 81 | AMFI `mov x0,#1; ret` patch + developer_mode toggle |
| `XPFWrapper` | 98 | Kernel symbol resolution via vendored libxpf |
| `SandboxEscape` | 57 | ucred sandbox label clearing via vendored C (`ds_get_our_proc()`) |
| `VirtualFileSystem` | 79 | VFS abstraction: read/write/listdir over `vfs_*` C shims |
| `RemoteCallEngine` | 92 | Mach exception thread hijack, `findProcess(named:)` via sysctl |
| `SpringBoardExecutor` | 68 | App bundle copy + uicache via SpringBoard RemoteCall |
| `ExploitViewModel` | 56 | startPipeline + startExploit with 11-stage progress tracking |

## Credits

- **DarkSword exploit** — rooootdev ([LARA](https://github.com/rooootdev/lara))
- **ChOma** — khanhduytran0 ([ChOma](https://github.com/khanhduytran0/ChOma))
- **XPF** — Linus Henze (Fugu14)
- **RemoteCall pattern** — LARA project
- **libgrabkernel2** — AlfieCG

## License

This project is provided for educational and security research purposes only.

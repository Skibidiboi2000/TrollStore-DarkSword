# TrollStore DarkSword

Unsigned IPA installer for iOS 17.0 – 26.0.1, powered by the DarkSword kernel exploit. Works on iPhone 7–16 and select iPads.

> **Note:** This project has been tested on iPad 9th gen (3 GB RAM, A12) — the exploit **fails on 3 GB devices** due to DarkSword's heap spray memory requirements. The app now detects this at startup and shows a clear error instead of hanging. Testing on a device with **≥6 GB RAM** is still needed to confirm full exploit success.
> 
> The pcbStartOffset fix, KASLR defeat dual-path, and RemoteCall stack fallback have been verified to compile for arm64 + arm64e on Xcode 27 beta.

## Quick Start

```bash
./build_ipa.sh
```

Output: `build/TrollStoreDarkSword.ipa` — sideload with Sideloadly or AltStore.

Requires Xcode 16+ (Xcode 27 beta recommended for latest SDK) and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The build script automatically detects Xcode-beta.app.

## Supported Versions

| iOS | Status |
|-----|--------|
| 17.0 – 26.0.1 | Supported |
| 26.1+ | Not Supported (patched) |
| 18.7.1+ | Not Supported (patched) |

All A10–A18 devices (iPhone 7–16). M5, A19 and A19 Pro are blocked by MTE hardware.

## Features

- IPA installation to `/Applications/` (system partition)
- 16+ entitlements injected via ChOma
- Sandbox escape + VFS file access
- uicache registration via SpringBoard RemoteCall
- Kernel patching (P_PLATFORM + mac_proc_enforce = 0)
- Post-exploit offset resolution via XPF (Fugu14)

## Known Issues

- wont work on M5, A19 and A19 Pro due to MTE
- the kernel may panic when the app is closed from the app switcher (same as LARA)
- doesnt work on **M-series iPads** (set `t1sz_boot = 0x11` in settings if you want to try)
- RemoteCall is buggy and may not work properly (no PAC bypass exists for arm64e on iOS 18+)
- **3 GB RAM devices are not supported** — the exploit needs more memory than iPad 9th gen has available (the app now detects this and exits early instead of hanging)

## Tips

- deleting and redownloading the kernelcache can fix many issues. before asking for help, try this first.
- if the exploit hangs, try setting a custom `icmp6_filter` offset in Settings → Modify Offsets (default is 0x138 for iOS 18+, 0x148 for iOS 17.x).
- the app keeps an audio session active during the exploit to prevent iOS from suspending the process.
- Settings → Modify Offsets now shows the correct default per iOS version.

## Credits

- **DarkSword exploit** — rooootdev ([LARA](https://github.com/rooootdev/lara))
- **ChOma** — khanhduytran0 ([ChOma](https://github.com/khanhduytran0/ChOma))
- **XPF** — Linus Henze (Fugu14)
- **Verified iOS 18 offsets** — Kev1nLevin ([darksword-kexploit-ios18](https://github.com/Kev1nLevin/darksword-kexploit-ios18))
- **libgrabkernel2** — AlfieCG
- **RemoteCall pattern** — LARA project

## License

Educational and security research purposes only.

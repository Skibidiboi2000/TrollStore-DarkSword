# TrollStore DarkSword

Unsigned IPA installer for iOS 17.0-26.x using the DarkSword kernel exploit.

## Architecture

```
App Launch → Coordinator → ds_run()
                               │
                    ┌──────────┴──────────┐
                    │                     │
               Exploit (ds)       Post-exploit (ObjC)
                    │                     │
               DarkSword KRW       Sandbox escape → P_PLATFORM
                    │                     │
               Kernel R/W           CDHash extraction → Trust Cache injection
                                         │
                                    IPA install (atomic rename to system container)
                                         │
                                    uicache via SpringBoard RemoteCall
```

### Exploit: DarkSword

- **Race-based OOB read/write** between `pwritev`/`preadv` and `mach_vm_map` (memory pressure)
- **Dynamic PCB discovery** via `inp_gencnt` — replaces old process-marker search that caused false positives
- **icmp6filt pointer corruption** on sprayed IPv6 ICMP sockets → early kernel R/W
- **Socket usecount bump** prevents GC, keeps KRW permanent
- **A18 vs non-A18 paths** — wired page strategy for iPhone 17,+ devices

### Post-Exploit

- **Sandbox escape** (sbx.m): patch MACF extension tokens, rewrite to read-write
- **P_PLATFORM**: set kernel flag on self proc
- **CDHash extraction** (ChOma): parse MachO code signature, get best hash
- **Trust cache injection**: write CDHash directly into AMFI trust cache via KRW
- **IPA install**: atomic `rename()` of extracted .app into `/var/containers/Bundle/Application/`
- **uicache** via SpringBoard RemoteCall

## Key Files

| File | Purpose |
|------|---------|
| `Vendored/darksword/darksword.m` | Core exploit — OOB race, PCB discovery, KRW |
| `Vendored/darksword/offsets.m` | Kernel struct offsets per iOS/XNU version |
| `Vendored/pe/sbx.m` | Sandbox escape |
| `Vendored/TaskRop/RemoteCall.m` | Mach RPC to SpringBoard |
| `Core/Coordinator/Coordinator.m` | Pipeline orchestrator |
| `Core/Kernel/TrustCacheManager.m` | Kernel trust cache injection |
| `Core/Kernel/KRWEngine.m` | KRW wrapper |
| `Core/Install/IPAInstaller.m` | IPA install logic |
| `Core/Install/IPAParser.m` | ZIP extraction, CDHash parsing |

## Changes from upstream

- Port from Swift + C to pure ObjC
- Dynamic proc scan replaces hardcoded offsets
- 3GB RAM device support (halved search mapping)
- XPF-based kernel offset auto-resolution
- **PCB discovery by `inp_gencnt`** — eliminates kernel panics from false-positive process-marker matches
- Structured exploit state: validation before corruption, retry instead of panic
- All struct fields validated (`le_next`, `le_prev`, `pcbinfo`, `socket`) before accepting a candidate PCB

## Build

```bash
./build_ipa.sh
```

Requires XcodeGen. Output: `build/TrollStoreDarkSword.ipa`

## Dependencies (vendored)

- **DarkSword** — kernel exploit
- **ChOma** — MachO parsing, trust cache
- **XPF** — kernel patchfinder
- **libgrabkernel2** — kernelcache downloader
- **TaskRop** — Mach IPC / RemoteCall
- **PE** — sandbox escape, vnode manipulation

## Supported Devices

iOS 17.0 through 26.x, ARM64 and ARM64e. A18 (iPhone 17,+) has a separate exploit path with wired-page strategy.

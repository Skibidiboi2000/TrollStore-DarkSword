# TrollStore DarkSword — Agent Context

> **Purpose**: This file documents critical architectural invariants, design decisions, and constraints
> of the TrollStore DarkSword project. If you are an LLM agent (Claude, ChatGPT, Gemini, etc.)
> asked to edit, refactor, or "fix" anything in this repo, **read this first** to avoid breaking
> the project's core design.

---

## 🚫 Do NOT Touch / Change

### 1. Code Signing — Must Always Be Disabled

```yaml
# project.yml
CODE_SIGN_STYLE: Manual
CODE_SIGN_IDENTITY: "-"
CODE_SIGNING_REQUIRED: NO
CODE_SIGNING_ALLOWED: NO
DEVELOPMENT_TEAM: ""
```

This app is **unsigned by design**. It gets sideloaded via Sideloadly/AltStore with a dev cert,
and the DarkSword exploit at runtime removes trust cache restrictions. **Never re-enable signing.**

### 2. 📍 Install Location — System `/Applications/` ONLY (NOT User)

> **🚨 CRITICAL — This is the core identity of TrollStore. Changing this breaks everything.**

TrollStore installs IPAs into **`/Applications/`** (the system app partition), NOT into the
user sandbox (`/var/containers/Bundle/Application/` or `~/Documents/` etc.).

**Why system install matters:**
- Installed apps **persist across reboots** without needing re-sideloading
- Apps appear as **system apps** with unrestricted entitlements
- Apps **survive** a signing certificate revoke or expiry
- This is **the entire point** of using a kernel exploit — to bypass user-container limits

**What happens if you change to user install:**
- Apps disappear after reboot
- Apps lose entitlements
- The app becomes just another sideloaded app — **TrollStore ceases to exist**

**Do NOT:**
- Change `/Applications/` to any user-space path (e.g. `NSDocumentDirectory`, `Caches`, `Library`)
- Add sandbox container installs as an "alternative" or fallback
- Use `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`
- Make install path configurable via settings
- "Fix" file permissions as if targeting user containers
- Refactor `IPAInstaller` to accept a destination path parameter

Relevant files:
- [IPAInstaller.swift](file:///Users/khangdeptrai/Desktop/Jailbreak/TrollStore/Core/Install/IPAInstaller.swift) — copies `.app` bundles into `/Applications/`
- [SpringBoardExecutor.swift](file:///Users/khangdeptrai/Desktop/Jailbreak/TrollStore/Core/RemoteCall/SpringBoardExecutor.swift) — uses `uicache` to register apps
- [InstallView.swift](file:///Users/khangdeptrai/Desktop/Jailbreak/TrollStore/UI/Views/InstallView.swift) — triggers the install flow after exploit

### 3. Architecture Targets — arm64 + arm64e Both Required

```yaml
# project.yml
ARCHS: "arm64 arm64e"
```

Both architectures are mandatory. arm64e covers modern A12+ devices (which have PAC).
Removing either architecture will break support for a large set of devices.

### 4. Deployment Target — iOS 17.0 Minimum

```yaml
IPHONEOS_DEPLOYMENT_TARGET: "17.0"
```

The DarkSword exploit targets iOS 17.0–26.x. **Never lower this to below 17.0**.
Raising it constrains the user base. The supported range is defined in:
[DeviceInfo.swift](file:///Users/khangdeptrai/Desktop/Jailbreak/TrollStore/Core/Model/DeviceInfo.swift)

### 5. `@Observable` Macro — Do Not Re-introduce

All three observable classes (`ContentCoordinator`, `ExploitViewModel`, `AppListViewModel`)
were deliberately migrated from `@Observable` to `ObservableObject` + `@Published` because
Xcode 26.5's iOS swift-plugin-server **cannot expand the `@Observable` macro** (it returns
malformed responses).

**Do NOT switch back to `@Observable`** unless you've verified the Xcode version supports it.

### 6. `.onChange` Closures — Single Parameter Only

All `.onChange(of:)` calls use single-parameter closures `{ value in }`. The iOS 26 SDK
removed the two-parameter `{ oldValue, newValue in }` signature. **Do not revert.**

### 7. Prebuilt Dylibs — Must Be Embedded

The vendored dylibs [libxpf.dylib](file:///Users/khangdeptrai/Desktop/Jailbreak/TrollStore/Vendored/lib/libxpf.dylib)
and [libgrabkernel2.dylib](file:///Users/khangdeptrai/Desktop/Jailbreak/TrollStore/Vendored/lib/libgrabkernel2.dylib)
are **prebuilt binary blobs**. Do NOT:
- Try to rebuild them from source (they come from external projects)
- Remove them
- Change the embed post-build script in [project.yml](file:///Users/khangdeptrai/Desktop/Jailbreak/TrollStore/project.yml)
- Link them statically

### 8. Kernel Exploit Chain — Do Not Modify Pipeline Order

The exploit pipeline in [ContentCoordinator.swift](file:///Users/khangdeptrai/Desktop/Jailbreak/TrollStore/ContentCoordinator.swift#L76-L147)
runs in a strict order:
1. **Kernel r/w obtained** (DarkSword exploit)
2. **Kernel base resolved** (via XPF)
3. **Kernel patches applied** (AMFI disable via `KernelPatcher.applyAll()`)
4. **Post-exploit offsets initialized** (`offsets_init()` — C module)
5. **Sandbox escape** (`SandboxEscape.clearSandbox()`)
6. **VFS init** (`VirtualFileSystem.initialize()`)

**Do not reorder these steps, skip any, or "optimize" the pipeline.** Each depends on
the previous.

### 9. XPF — Do Not Replace or Remove

XPF (XNU Platform Finder, from Fugu14 by Linus Henze) is the offset resolution engine.
It resolves kernel structure offsets dynamically at runtime. The code uses it through:
- [XPFWrapper.swift](file:///Users/khangdeptrai/Desktop/Jailbreak/TrollStore/Core/Kernel/XPFWrapper.swift)
- The C-side `xpf_stop()` call inside `offsets_init()`

**Do NOT replace XPF with hardcoded offsets** — that would break across iOS versions.

### 10. ChOma — Do Not Touch

ChOma (by khanhduytran0) is a vendored C library for Mach-O parsing and trust cache
injection. It's used via [ChoMAWrapper.swift](file:///Users/khangdeptrai/Desktop/Jailbreak/TrollStore/Vendored/ChOma/ChoMAWrapper.swift).
Do not modify, refactor, or replace this library unless you fully understand the
trust cache injection format.

---

## ✅ Important Patterns to Preserve

### File Picker Uses System UTType Tag

In [InstallView.swift](file:///Users/khangdeptrai/Desktop/Jailbreak/TrollStore/UI/Views/InstallView.swift#L6):

```swift
UTType(tag: "ipa", tagClass: .filenameExtension, conformingTo: .archive)
```

This uses the **system `.ipa` extension tag**, NOT a custom exported UTI. Custom UTIs
make `.ipa` files invisible in the system file picker. Keep this pattern.

### Swift 6 + Strict Concurrency

The project uses `swift-version 6` and `@MainActor` / `@EnvironmentObject` pattern.
Do not downgrade Swift version or remove `@MainActor` annotations — the code relies
on strict concurrency for safety with the kernel R/W handle.

### PersistenceService Is NSLock-based

[PersistenceService.swift](file:///Users/khangdeptrai/Desktop/Jailbreak/TrollStore/Services/PersistenceService.swift)
uses `UserDefaults` + `NSLock.withLock` for thread-safe app list persistence.
Do not replace with CoreData or SwiftData — the app list is intentionally simple
and must survive kernel panics (UserDefaults flushes synchronously).

### LogManager Is a Singleton

[LogManager.swift](file:///Users/khangdeptrai/Desktop/Jailbreak/TrollStore/Services/LogManager.swift)
is a global singleton accessed via `LogManager.shared`. It must work before and after
the exploit. Do not convert to dependency injection.

### RemoteCall Uses Kernel R/W for Process Execution

[RemoteCallEngine.swift](file:///Users/khangdeptrai/Desktop/Jailbreak/TrollStore/Core/RemoteCall/RemoteCallEngine.swift)
uses kernel memory read/write to execute code in SpringBoard's process. This is NOT
XPC or Mach IPC. Do not replace it with platform APIs — sandbox restrictions prevent
normal inter-process communication.

---

## 💡 Build System

| Command | Purpose |
|---------|---------|
| `xcodegen generate` | Regenerate `.xcodeproj` from [project.yml](file:///Users/khangdeptrai/Desktop/Jailbreak/TrollStore/project.yml) |
| `./build_ipa.sh` | Full clean build → `.ipa` (runs xcodegen + xcodebuild + packaging) |
| `xcodebuild -project ... build` | Direct build (use after xcodegen) |

**Do NOT try `swift build`** — SPM cannot link prebuilt dylibs or process the
bridging header. Always use xcodegen + xcodebuild.

The build output goes to `build/TrollStoreDarkSword.ipa`.

---

### 🚨 If Unsure, Ask

If you're considering a change that conflicts with anything above,
**stop and reconsider**. The architecture is purpose-built for an unsigned,
post-exploit system app installer. Generic SwiftUI best practices often do
not apply.

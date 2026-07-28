# KSU Toast

Notification-based root authorization for KernelSU Next.

When an app requests root, KSU Toast shows a notification with **Grant / Deny / Ignore** buttons instead of requiring you to open the KSU Manager app to toggle permissions.

## How it works

```
App calls su
    │
    ▼
su wrapper (replaces /system/bin/su)
    ├── Already allowed → passes through to real ksud → root granted normally
    ├── Already denied  → exits with error
    └── Unknown → asks you via notification
                      │
                  [Grant] → app added to allowlist, root granted
                  [Deny]  → app added to deny list, won't ask again
                  [Ignore]→ request denied, app can ask again later
```

## Architecture

| Component | Role |
|-----------|------|
| **su-wrapper** | Thin C binary replacing `/system/bin/su`. Captures the calling app's UID and asks the daemon for permission before passing through to the real `ksud`. |
| **ksu-toastd** | Root daemon. Maintains allow.cache and deny.list. When a new app requests root, it signals the companion APK. On grant, it calls `KSU_IOCTL_SET_APP_PROFILE` via `setuid(manager_uid)` impersonation — no KSU kernel edits. |
| **Companion APK** | Foreground service. Listens on a Unix socket, posts notifications with action buttons. ~50KB, no UI. |

## Requirements

- KernelSU Next with working root
- Android 9+ (API 28+)
- ARM64 device

## Installation

1. Download the latest `.zip` from [Releases](https://github.com/WildKernels/ksu-toast/releases)
2. Open KSU Next Manager → Modules → Install from storage
3. Select the zip
4. Reboot

After reboot, grant KSU Toast the notification permission when prompted.

## Building locally

### Prerequisites

- Android NDK r27+ (for ARM64 C binaries)
- Android SDK + Gradle (for the APK)
- Set `ANDROID_NDK_HOME` to your NDK path

### Build commands

```bash
# Full build + zip
make VERSION=1 release

# Just build binaries
make wrapper daemon

# Build APK
make apk

# Clean
make clean
```

### CI builds

Push to `main` or use the manual workflow dispatch → GitHub Actions builds everything and creates an auto-incrementing release.

## Development

The project structure:

```
ksu-toast/
├── module.prop              # KSU module metadata
├── customize.sh             # Module installer script
├── post-fs-data.sh          # Boot: installs APK
├── service.sh               # Boot: starts daemon
├── sepolicy.rule            # SELinux rules
├── Makefile                 # Top-level build
├── wrapper/
│   ├── su-wrapper.c         # su replacement binary
│   └── Makefile
├── daemon/
│   ├── ksu-toastd.c         # Root daemon
│   └── Makefile
├── apk/                     # Companion Android app
│   ├── settings.gradle.kts
│   ├── build.gradle.kts
│   └── app/
└── .github/workflows/
    └── build.yml            # Auto-build + release
```

## License

MIT

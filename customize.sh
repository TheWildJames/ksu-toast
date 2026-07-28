#!/system/bin/sh

# KSU Toast - Module Installer
# Runs during module installation via KSU Manager

# MODPATH is set by KSU Manager to the module's working directory.
# Fall back to MODDIR (from script location) if MODPATH isn't set.
MODPATH=${MODPATH:-${0%/*}}
PERSISTENT_DIR=/data/adb/ksu-toast

ui_print "- Installing KSU Toast v${VERSION:-unknown}"

# Ensure persistent directory exists
mkdir -p "$PERSISTENT_DIR"
mkdir -p "$PERSISTENT_DIR/config"

# Copy daemon binary
cp "$MODPATH/daemon/ksu-toastd" "$PERSISTENT_DIR/ksu-toastd"
chmod 0755 "$PERSISTENT_DIR/ksu-toastd"

# Initialize deny list and allow cache
touch "$PERSISTENT_DIR/deny.list"
touch "$PERSISTENT_DIR/allow.cache"
chmod 0644 "$PERSISTENT_DIR/deny.list"
chmod 0644 "$PERSISTENT_DIR/allow.cache"

# Find and install companion APK — try multiple paths
APK_SOURCE=""
for candidate in \
    "$MODPATH/apk/KsuToast.apk" \
    "${0%/*}/apk/KsuToast.apk" \
    "/data/adb/modules/${MODID:-ksu_toast}/apk/KsuToast.apk" \
    "/data/adb/modules_update/${MODID:-ksu_toast}/apk/KsuToast.apk"; do
    if [ -f "$candidate" ]; then
        APK_SOURCE="$candidate"
        break
    fi
done

if [ -n "$APK_SOURCE" ]; then
    ui_print "- Found APK at: $APK_SOURCE"
    cp "$APK_SOURCE" "$PERSISTENT_DIR/KsuToast.apk"
    chmod 0644 "$PERSISTENT_DIR/KsuToast.apk"

    # Install via package manager
    pm install -r "$PERSISTENT_DIR/KsuToast.apk" 2>&1 </dev/null | grep -v "^\s*$"

    if pm path com.wildkernels.ksutoast >/dev/null 2>&1; then
        ui_print "- Companion APK installed"
    else
        ui_print "- APK will install on next boot (boot-completed)"
    fi
else
    ui_print "- WARNING: KsuToast.apk not found"
    ui_print "- Searched: apk/ in module directory"
fi

# Also copy APK to persistent storage for boot-completed.sh to use
if [ -f "$PERSISTENT_DIR/KsuToast.apk" ]; then
    # Already copied above
    :
elif [ -f "$MODPATH/KsuToast.apk" ]; then
    cp "$MODPATH/KsuToast.apk" "$PERSISTENT_DIR/KsuToast.apk"
fi

ui_print "- Installation complete"
ui_print "- Reboot to activate KSU Toast"

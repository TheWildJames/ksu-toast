#!/system/bin/sh

# KSU Toast - Module Installer
# Runs during module installation via KSU Manager

MODDIR=${0%/*}
PERSISTENT_DIR=/data/adb/ksu-toast

ui_print "- Installing KSU Toast v${VERSION}"

# Ensure persistent directory exists
mkdir -p "$PERSISTENT_DIR"
mkdir -p "$PERSISTENT_DIR/config"

# Copy daemon binary
cp "$MODDIR/daemon/ksu-toastd" "$PERSISTENT_DIR/ksu-toastd"
chmod 0755 "$PERSISTENT_DIR/ksu-toastd"

# Initialize deny list and allow cache
touch "$PERSISTENT_DIR/deny.list"
touch "$PERSISTENT_DIR/allow.cache"
chmod 0644 "$PERSISTENT_DIR/deny.list"
chmod 0644 "$PERSISTENT_DIR/allow.cache"

# Install companion APK — pm works here during module installation
if [ -f "$MODDIR/apk/KsuToast.apk" ]; then
    cp "$MODDIR/apk/KsuToast.apk" "$PERSISTENT_DIR/KsuToast.apk"
    chmod 0644 "$PERSISTENT_DIR/KsuToast.apk"
    pm install -r "$PERSISTENT_DIR/KsuToast.apk" 2>&1 </dev/null | grep -v "^\s*$"
    if pm path com.wildkernels.ksutoast >/dev/null 2>&1; then
        ui_print "- Companion APK installed"
    else
        ui_print "- Companion APK will install on next boot"
    fi
else
    ui_print "- WARNING: KsuToast.apk not found in module"
fi

ui_print "- Installation complete"
ui_print "- Reboot to activate KSU Toast"

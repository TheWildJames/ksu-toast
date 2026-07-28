#!/system/bin/sh
PATH=/data/adb/ksu/bin:$PATH

# MODPATH is set by KSU Manager to the module's temp install directory.
# Fall back to script-location-based path if not set.
MODPATH=${MODPATH:-${0%/*}}
PERSISTENT_DIR=/data/adb/ksu-toast

# grab version from module.prop
versionCode=$(grep versionCode "$MODPATH/module.prop" | sed 's/versionCode=//g' )

ui_print "- Installing KSU Toast v$versionCode"

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

# Install companion APK
if [ -f "$MODPATH/apk/KsuToast.apk" ]; then
    ui_print "- Found APK at $MODPATH/apk/KsuToast.apk"
    cp "$MODPATH/apk/KsuToast.apk" "$PERSISTENT_DIR/KsuToast.apk"
    chmod 0644 "$PERSISTENT_DIR/KsuToast.apk"
    pm install -r "$PERSISTENT_DIR/KsuToast.apk" 2>&1 </dev/null | grep -v "^\s*$"
    if pm path com.wildkernels.ksutoast >/dev/null 2>&1; then
        ui_print "- Companion APK installed"
    else
        ui_print "- APK will install on next boot"
    fi
else
    ui_print "- WARNING: KsuToast.apk not found at $MODPATH/apk/KsuToast.apk"
    ui_print "- Contents of module:"
    ls -la "$MODPATH/" 2>/dev/null | while read line; do ui_print "  $line"; done
fi

ui_print "- Installation complete"
ui_print "- Reboot to activate KSU Toast"

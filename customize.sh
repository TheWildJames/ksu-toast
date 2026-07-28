#!/system/bin/sh
PATH=/data/adb/ksu/bin:$PATH

# MODPATH is set by KSU Manager to the module's temp install directory
MODPATH=${MODPATH:-${0%/*}}
PERSISTENT_DIR=/data/adb/ksu-toast

# ── Architecture check (ARM64 only) ───────────────────────
ARCH=$(uname -m)
case "$ARCH" in
    aarch64|arm64)
        ui_print "- Architecture: $ARCH (supported)"
        ;;
    *)
        ui_print "! ERROR: Unsupported architecture: $ARCH"
        ui_print "! KSU Toast requires ARM64 (aarch64)"
        abort "Aborting installation"
        ;;
esac

# Grab version from module.prop
versionCode=$(grep versionCode "$MODPATH/module.prop" | sed 's/versionCode=//g' )
ui_print "- Installing KSU Toast v$versionCode"

# ── Install companion APK ─────────────────────────────────
# Install directly from module's apk/ directory.
# APK is debug-signed (see app/build.gradle.kts) so pm accepts it.
APK_SRC="$MODPATH/apk/KsuToast.apk"
if [ -f "$APK_SRC" ]; then
    ui_print "- Found APK ($(wc -c < "$APK_SRC") bytes)"
    cp "$APK_SRC" "$PERSISTENT_DIR/KsuToast.apk"
    chmod 0644 "$PERSISTENT_DIR/KsuToast.apk"

    # Install via package manager — retry a few times
    for attempt in 1 2 3; do
        INSTALL_OUT=$(pm install -r "$PERSISTENT_DIR/KsuToast.apk" 2>&1 </dev/null)
        if echo "$INSTALL_OUT" | grep -q "Success\|Success$"; then
            ui_print "- Companion APK installed (attempt $attempt)"
            break
        else
            [ "$attempt" -lt 3 ] && sleep 1
            if [ "$attempt" -eq 3 ]; then
                ui_print "- pm install output: $INSTALL_OUT"
                ui_print "- APK saved — will retry on next boot"
            fi
        fi
    done
else
    ui_print "- WARNING: KsuToast.apk not found at $APK_SRC"
    ui_print "- Module contents:"
    ls -la "$MODPATH/" 2>/dev/null | while read line; do ui_print "  $line"; done
fi

# ── Setup persistent files ────────────────────────────────
mkdir -p "$PERSISTENT_DIR"
mkdir -p "$PERSISTENT_DIR/config"
touch "$PERSISTENT_DIR/deny.list"
touch "$PERSISTENT_DIR/allow.cache"
chmod 0644 "$PERSISTENT_DIR/deny.list"
chmod 0644 "$PERSISTENT_DIR/allow.cache"

# Copy daemon binary
cp "$MODPATH/daemon/ksu-toastd" "$PERSISTENT_DIR/ksu-toastd"
chmod 0755 "$PERSISTENT_DIR/ksu-toastd"

ui_print "- Installation complete"
ui_print "- Reboot to activate KSU Toast"

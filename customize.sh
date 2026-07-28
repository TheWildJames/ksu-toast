#!/system/bin/sh
PATH=/data/adb/ksu/bin:$PATH

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

# ── Kill old daemon if running (so we can overwrite binary) ──
OLD_PID=$(cat "$PERSISTENT_DIR/daemon.pid" 2>/dev/null || echo "")
if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID" 2>/dev/null
    sleep 1
    ui_print "- Stopped old daemon (pid: $OLD_PID)"
fi
rm -f "$PERSISTENT_DIR/daemon.sock" "$PERSISTENT_DIR/apk.sock"

# ── Copy daemon binary ────────────────────────────────────
mkdir -p "$PERSISTENT_DIR"
cp "$MODPATH/daemon/ksu-toastd" "$PERSISTENT_DIR/ksu-toastd"
chmod 0755 "$PERSISTENT_DIR/ksu-toastd"

# ── Setup deny list and cache ─────────────────────────────
touch "$PERSISTENT_DIR/deny.list"
touch "$PERSISTENT_DIR/allow.cache"
chmod 0644 "$PERSISTENT_DIR/deny.list"
chmod 0644 "$PERSISTENT_DIR/allow.cache"

# ── Install companion APK ─────────────────────────────────
# SELinux blocks pm install from /data/adb/ (adb_data_file context).
# Must copy to /data/local/tmp/ where system_server can read it.
APK_SRC="$MODPATH/apk/KsuToast.apk"
TMP_APK="/data/local/tmp/KsuToast.apk"

if [ -f "$APK_SRC" ]; then
    ui_print "- Found APK ($(wc -c < "$APK_SRC") bytes)"

    # Keep a copy in persistent storage for boot-completed.sh
    cp "$APK_SRC" "$PERSISTENT_DIR/KsuToast.apk"
    chmod 0644 "$PERSISTENT_DIR/KsuToast.apk"

    # Copy to /data/local/tmp for SELinux-friendly pm install
    cp "$APK_SRC" "$TMP_APK"
    chmod 0644 "$TMP_APK"

    # Install via package manager
    INSTALL_OUT=$(pm install -r "$TMP_APK" 2>&1 </dev/null)
    rm -f "$TMP_APK"

    if echo "$INSTALL_OUT" | grep -q "Success"; then
        ui_print "- Companion APK installed"
    else
        ui_print "- pm install: $(echo "$INSTALL_OUT" | tail -1)"
        ui_print "- Will retry on next boot"
    fi
else
    ui_print "- WARNING: KsuToast.apk not found at $APK_SRC"
fi

ui_print "- Installation complete"
ui_print "- Reboot to activate KSU Toast"

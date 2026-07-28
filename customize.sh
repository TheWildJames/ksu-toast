#!/system/bin/sh
PATH=/data/adb/ksu/bin:$PATH

MODPATH=${MODPATH:-${0%/*}}
PERSISTENT_DIR=/data/adb/ksu-toast

# ── Architecture check ────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
    aarch64|arm64)
        ui_print "- Architecture: $ARCH (supported)"
        ;;
    *)
        ui_print "! ERROR: Unsupported architecture: $ARCH"
        abort "Aborting: KSU Toast requires ARM64"
        ;;
esac

versionCode=$(grep versionCode "$MODPATH/module.prop" | sed 's/versionCode=//g')
ui_print "- Installing KSU Toast v$versionCode"

# ── Persistent data directory ─────────────────────────────
# Only for runtime data (sockets, pid, deny list, cache)
# Binaries stay in the module directory — no copy needed
mkdir -p "$PERSISTENT_DIR"

touch "$PERSISTENT_DIR/deny.list"
touch "$PERSISTENT_DIR/allow.cache"
chmod 0644 "$PERSISTENT_DIR/deny.list"
chmod 0644 "$PERSISTENT_DIR/allow.cache"

# ── Install companion APK ─────────────────────────────────
# SELinux blocks pm install from /data/adb/, so we copy to
# /data/local/tmp/ first, then discard after install.
APK_SRC="$MODPATH/apk/KsuToast.apk"
TMP_APK="/data/local/tmp/KsuToast.apk"

if [ -f "$APK_SRC" ]; then
    ui_print "- Found APK ($(wc -c < "$APK_SRC") bytes)"
    cp "$APK_SRC" "$TMP_APK"
    chmod 0644 "$TMP_APK"

    INSTALL_OUT=$(pm install -r "$TMP_APK" 2>&1 </dev/null)
    rm -f "$TMP_APK"

    if echo "$INSTALL_OUT" | grep -q "Success"; then
        ui_print "- Companion APK installed"
    else
        ui_print "- pm install: $(echo "$INSTALL_OUT" | tail -1)"
    fi
else
    ui_print "- WARNING: KsuToast.apk not found at $APK_SRC"
fi

ui_print "- Installation complete"
ui_print "- Reboot to activate KSU Toast"

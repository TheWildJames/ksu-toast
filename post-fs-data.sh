#!/system/bin/sh

# KSU Toast - post-fs-data.sh
# Installs companion APK on every boot (in case it was removed)

MODDIR=${0%/*}

# Install/update companion APK if it exists in our module
if [ -f "$MODDIR/apk/KsuToast.apk" ]; then
    cp "$MODDIR/apk/KsuToast.apk" /data/adb/ksu-toast/KsuToast.apk
    chmod 0644 /data/adb/ksu-toast/KsuToast.apk

    # Install the APK (package manager)
    # Use pm install with -r to reinstall if already present
    if [ -f /data/adb/ksu-toast/KsuToast.apk ]; then
        pm install -r /data/adb/ksu-toast/KsuToast.apk 2>/dev/null || true
    fi
fi

# Default timeout for root request (seconds)
setprop ksu.toast.timeout 10

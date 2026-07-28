#!/system/bin/sh

# KSU Toast - Module Installer
# This runs during module installation via the KSU Manager

MODDIR=${0%/*}

ui_print "- Installing KSU Toast v${VERSION}"

# Ensure directories exist
mkdir -p /data/adb/ksu-toast

# Copy daemon binary
cp "$MODDIR/daemon/ksu-toastd" /data/adb/ksu-toast/ksu-toastd
chmod 0755 /data/adb/ksu-toast/ksu-toastd

# Install companion APK
cp "$MODDIR/apk/KsuToast.apk" /data/adb/ksu-toast/KsuToast.apk
chmod 0644 /data/adb/ksu-toast/KsuToast.apk

# Create config directory
mkdir -p /data/adb/ksu-toast/config
touch /data/adb/ksu-toast/deny.list
touch /data/adb/ksu-toast/allow.cache
chmod 0644 /data/adb/ksu-toast/deny.list
chmod 0644 /data/adb/ksu-toast/allow.cache

# Create sepolicy backup dir
mkdir -p /data/adb/ksu-toast/sepolicy

ui_print "- Installation complete"
ui_print "- Reboot to activate KSU Toast"

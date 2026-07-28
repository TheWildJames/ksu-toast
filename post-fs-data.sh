#!/system/bin/sh

# KSU Toast - post-fs-data.sh
# Early boot script. Runs before system is fully booted.
# Just ensures data directory exists — APK install and daemon
# start happen in boot-completed.sh where pm is available.

MODDIR=${0%/*}
PERSISTENT_DIR=/data/adb/ksu-toast

mkdir -p "$PERSISTENT_DIR/config"

# Set default timeout (seconds) for root request UI
setprop ksu.toast.timeout 10

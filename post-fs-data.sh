#!/system/bin/sh

# KSU Toast - post-fs-data.sh
# Early boot — set default timeout if not already configured.

mkdir -p /data/adb/ksu-toast/config

# Only set default if not already configured (don't overwrite user's value)
CURRENT=$(getprop ksu.toast.timeout 2>/dev/null)
if [ -z "$CURRENT" ] || [ "$CURRENT" = "0" ]; then
    setprop ksu.toast.timeout 10
fi

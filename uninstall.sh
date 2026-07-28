#!/system/bin/sh

# KSU Toast - Uninstall script
# Runs when the module is removed via KSU Manager.
# Cleans up: companion APK, persistent data, sockets.

echo "[ksu-toast] Uninstalling..."

# Remove companion APK
if pm path com.wildkernels.ksutoast >/dev/null 2>&1; then
    pm uninstall com.wildkernels.ksutoast 2>&1 </dev/null | grep -v "^\s*$"
    echo "[ksu-toast] Companion APK removed"
fi

# Kill daemon if running
DAEMON_PID=/data/adb/ksu-toast/daemon.pid
if [ -f "$DAEMON_PID" ]; then
    PID=$(cat "$DAEMON_PID" 2>/dev/null)
    [ -n "$PID" ] && kill "$PID" 2>/dev/null
    rm -f "$DAEMON_PID"
fi

# Remove persistent data and sockets
rm -f /data/adb/ksu-toast/daemon.sock
rm -f /data/adb/ksu-toast/apk.sock
rm -f /data/adb/ksu-toast/daemon.log

# Remove deny list and cache (user may want to keep — skip with KEEP_CONFIG=1)
if [ "$KEEP_CONFIG" != "1" ]; then
    rm -f /data/adb/ksu-toast/deny.list
    rm -f /data/adb/ksu-toast/allow.cache
    rm -rf /data/adb/ksu-toast/config
fi

echo "[ksu-toast] Uninstall complete"

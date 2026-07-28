#!/system/bin/sh

# KSU Toast - service.sh
# Starts the ksu-toastd daemon in late_start service mode

MODDIR=${0%/*}
DAEMON=/data/adb/ksu-toast/ksu-toastd
CONFIG=/data/adb/ksu-toast/config
DENY_LIST=/data/adb/ksu-toast/deny.list
CACHE=/data/adb/ksu-toast/allow.cache
SOCKET=/data/adb/ksu-toast/daemon.sock
APK_SOCKET=/data/adb/ksu-toast/apk.sock

# Ensure config dir exists
mkdir -p "$CONFIG"
touch "$DENY_LIST" "$CACHE"

# Kill any existing daemon
if [ -f "$SOCKET" ]; then
    kill "$(cat /data/adb/ksu-toast/daemon.pid 2>/dev/null)" 2>/dev/null || true
    rm -f "$SOCKET" "$APK_SOCKET"
fi

# Start daemon
if [ -x "$DAEMON" ]; then
    # Run in standalone shell mode via KSU BusyBox
    ASH_STANDALONE=1 "$DAEMON" \
        --socket "$SOCKET" \
        --apk-socket "$APK_SOCKET" \
        --deny-list "$DENY_LIST" \
        --cache "$CACHE" \
        --config "$CONFIG" &
    
    echo $! > /data/adb/ksu-toast/daemon.pid
    
    # Give it time to bind the socket
    sleep 1
    
    if [ -S "$SOCKET" ]; then
        echo "[ksu-toast] Daemon started (pid: $(cat /data/adb/ksu-toast/daemon.pid))"
    else
        echo "[ksu-toast] Daemon failed to start"
    fi
fi

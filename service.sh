#!/system/bin/sh

# KSU Toast - service.sh
# late_start service mode. Hardcoded MODDIR — same reason as boot-completed.

MODDIR=/data/adb/modules/ksu_toast
PERSISTENT_DIR=/data/adb/ksu-toast
SOCKET="$PERSISTENT_DIR/daemon.sock"
APK_SOCKET="$PERSISTENT_DIR/apk.sock"
DENY_LIST="$PERSISTENT_DIR/deny.list"
CACHE="$PERSISTENT_DIR/allow.cache"
DAEMON="$MODDIR/daemon/ksu-toastd"
DAEMON_PID="$PERSISTENT_DIR/daemon.pid"
LOG="$PERSISTENT_DIR/daemon.log"

# Only start if daemon isn't already running
if [ -f "$DAEMON_PID" ]; then
    PID=$(cat "$DAEMON_PID" 2>/dev/null)
    [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null && exit 0
fi

rm -f "$SOCKET" "$APK_SOCKET"

# If daemon not at expected path, try to find it elsewhere in module
if [ ! -x "$DAEMON" ]; then
    FOUND=$(find "$MODDIR" -name "ksu-toastd" -type f 2>/dev/null | head -1)
    if [ -n "$FOUND" ] && [ "$FOUND" != "$DAEMON" ]; then
        cp "$FOUND" "$DAEMON" 2>/dev/null
        chmod 0755 "$DAEMON" 2>/dev/null
    fi
fi

if [ -x "$DAEMON" ]; then
    mkdir -p "$PERSISTENT_DIR"
    ASH_STANDALONE=1 "$DAEMON" \
        --socket "$SOCKET" \
        --apk-socket "$APK_SOCKET" \
        --deny-list "$DENY_LIST" \
        --cache "$CACHE" \
        --config "$PERSISTENT_DIR/config" \
        > "$LOG" 2>&1 &
    echo $! > "$DAEMON_PID"
    sleep 1

    if [ -S "$SOCKET" ]; then
        echo "[ksu-toast] Daemon started (pid: $(cat $DAEMON_PID))"
    else
        echo "[ksu-toast] Daemon failed to start — check $LOG"
    fi
else
    echo "[ksu-toast] Daemon binary not found at $DAEMON" >> "$LOG" 2>/dev/null || true
fi

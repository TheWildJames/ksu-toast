#!/system/bin/sh

# KSU Toast - service.sh
# late_start service mode script.
# Falls back to starting daemon if boot-completed.sh didn't run.

MODDIR="${0%/*}"
PERSISTENT_DIR=/data/adb/ksu-toast
SOCKET="$PERSISTENT_DIR/daemon.sock"
APK_SOCKET="$PERSISTENT_DIR/apk.sock"
DENY_LIST="$PERSISTENT_DIR/deny.list"
CACHE="$PERSISTENT_DIR/allow.cache"
# Daemon binary lives in module dir
DAEMON="$MODDIR/daemon/ksu-toastd"
DAEMON_PID="$PERSISTENT_DIR/daemon.pid"

# Only start if daemon isn't already running
if [ -f "$DAEMON_PID" ]; then
    PID=$(cat "$DAEMON_PID" 2>/dev/null)
    [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null && exit 0
fi

rm -f "$SOCKET" "$APK_SOCKET"

if [ -x "$DAEMON" ]; then
    ASH_STANDALONE=1 "$DAEMON" \
        --socket "$SOCKET" \
        --apk-socket "$APK_SOCKET" \
        --deny-list "$DENY_LIST" \
        --cache "$CACHE" \
        --config "$PERSISTENT_DIR/config" \
        > "$PERSISTENT_DIR/daemon.log" 2>&1 &
    echo $! > "$DAEMON_PID"
    sleep 1

    if [ -S "$SOCKET" ]; then
        echo "[ksu-toast] Daemon started (pid: $(cat $DAEMON_PID))"
    else
        echo "[ksu-toast] Daemon failed to start — check daemon.log"
    fi
fi

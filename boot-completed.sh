#!/system/bin/sh

# KSU Toast - boot-completed.sh
# Runs after system is fully booted.
# MODDIR is hardcoded — KSU may invoke scripts with a relative $0,
# and ${0%/*} would resolve to '.' instead of the module path.

MODDIR=/data/adb/modules/ksu_toast
PERSISTENT_DIR=/data/adb/ksu-toast
SOCKET="$PERSISTENT_DIR/daemon.sock"
APK_SOCKET="$PERSISTENT_DIR/apk.sock"
DENY_LIST="$PERSISTENT_DIR/deny.list"
CACHE="$PERSISTENT_DIR/allow.cache"
DAEMON="$MODDIR/daemon/ksu-toastd"
DAEMON_PID="$PERSISTENT_DIR/daemon.pid"
LOG="$PERSISTENT_DIR/daemon.log"

mkdir -p "$PERSISTENT_DIR"

# 1. Install companion APK if needed
if ! pm path com.wildkernels.ksutoast >/dev/null 2>&1; then
    if [ -f "$MODDIR/apk/KsuToast.apk" ]; then
        cp "$MODDIR/apk/KsuToast.apk" /data/local/tmp/KsuToast.apk
        pm install -r /data/local/tmp/KsuToast.apk 2>&1 </dev/null | grep -v "^\s*$"
        rm -f /data/local/tmp/KsuToast.apk
    fi
fi

# 2. Start daemon if not already running
if [ -f "$DAEMON_PID" ]; then
    PID=$(cat "$DAEMON_PID" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "[ksu-toast] Daemon already running (pid: $PID)"
        am start-foreground-service -n com.wildkernels.ksutoast/.MainService >/dev/null 2>&1 || true
        exit 0
    fi
fi

rm -f "$SOCKET" "$APK_SOCKET" "$DAEMON_PID"

if [ -x "$DAEMON" ]; then
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
        ls -la "$DAEMON" >> "$LOG" 2>&1
    fi
else
    echo "[ksu-toast] Daemon binary not found at $DAEMON" >> "$LOG"
fi

# 3. Start companion APK foreground service
if pm path com.wildkernels.ksutoast >/dev/null 2>&1; then
    am start-foreground-service -n com.wildkernels.ksutoast/.MainService >/dev/null 2>&1 || true
fi

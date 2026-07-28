#!/system/bin/sh

# KSU Toast - boot-completed.sh
# Runs after system is fully booted.

MODDIR="${0%/*}"
PERSISTENT_DIR=/data/adb/ksu-toast
SOCKET="$PERSISTENT_DIR/daemon.sock"
APK_SOCKET="$PERSISTENT_DIR/apk.sock"
DENY_LIST="$PERSISTENT_DIR/deny.list"
CACHE="$PERSISTENT_DIR/allow.cache"
# Daemon binary lives in module dir — no extra copy needed
DAEMON="$MODDIR/daemon/ksu-toastd"
DAEMON_PID="$PERSISTENT_DIR/daemon.pid"

# Ensure persistent dir exists
mkdir -p "$PERSISTENT_DIR"

# 1. Install/update companion APK if needed
if ! pm path com.wildkernels.ksutoast >/dev/null 2>&1; then
    # Try from module's apk/ dir
    if [ -f "$MODDIR/apk/KsuToast.apk" ]; then
        cp "$MODDIR/apk/KsuToast.apk" /data/local/tmp/KsuToast.apk
        pm install -r /data/local/tmp/KsuToast.apk 2>&1 </dev/null | grep -v "^\s*$"
        rm -f /data/local/tmp/KsuToast.apk
    fi
fi

if pm path com.wildkernels.ksutoast >/dev/null 2>&1; then
    echo "[ksu-toast] Companion APK installed"
fi

# 2. Start daemon if not already running
if [ -f "$DAEMON_PID" ]; then
    PID=$(cat "$DAEMON_PID" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "[ksu-toast] Daemon already running (pid: $PID)"
        # Still start APK service even if daemon is running
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
        > "$PERSISTENT_DIR/daemon.log" 2>&1 &
    echo $! > "$DAEMON_PID"
    sleep 1

    if [ -S "$SOCKET" ]; then
        echo "[ksu-toast] Daemon started (pid: $(cat $DAEMON_PID))"
    else
        echo "[ksu-toast] Daemon failed to start — check daemon.log"
    fi
else
    echo "[ksu-toast] Daemon binary not found at $DAEMON"
fi

# 3. Start companion APK foreground service
if pm path com.wildkernels.ksutoast >/dev/null 2>&1; then
    am start-foreground-service -n com.wildkernels.ksutoast/.MainService >/dev/null 2>&1 || true
fi

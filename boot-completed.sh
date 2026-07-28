#!/system/bin/sh

# KSU Toast - boot-completed.sh
# Runs after system is fully booted.
# Ensures the companion APK is installed and daemon is running.

MODDIR=${0%/*}
PERSISTENT_DIR=/data/adb/ksu-toast
SOCKET="$PERSISTENT_DIR/daemon.sock"
APK_SOCKET="$PERSISTENT_DIR/apk.sock"
DENY_LIST="$PERSISTENT_DIR/deny.list"
CACHE="$PERSISTENT_DIR/allow.cache"
DAEMON="$PERSISTENT_DIR/ksu-toastd"
DAEMON_PID="$PERSISTENT_DIR/daemon.pid"

# 1. Install/update companion APK if packaged
if [ -f "$MODDIR/apk/KsuToast.apk" ]; then
    cp "$MODDIR/apk/KsuToast.apk" "$PERSISTENT_DIR/KsuToast.apk"
    chmod 0644 "$PERSISTENT_DIR/KsuToast.apk"
    pm install -r "$PERSISTENT_DIR/KsuToast.apk" 2>&1 </dev/null | grep -v "^\s*$"
elif [ -f "$PERSISTENT_DIR/KsuToast.apk" ]; then
    # Fallback — reinstall from persistent storage
    pm install -r "$PERSISTENT_DIR/KsuToast.apk" 2>&1 </dev/null | grep -v "^\s*$"
fi

if pm path com.wildkernels.ksutoast >/dev/null 2>&1; then
    echo "[ksu-toast] Companion APK is installed"
else
    echo "[ksu-toast] WARNING: Companion APK not installed"
fi

# 2. Start daemon if not already running
if [ -f "$DAEMON_PID" ]; then
    PID=$(cat "$DAEMON_PID" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "[ksu-toast] Daemon already running (pid: $PID)"
        exit 0
    fi
fi

# Clean up stale socket
rm -f "$SOCKET" "$APK_SOCKET" "$DAEMON_PID"

# Start daemon
if [ -x "$DAEMON" ]; then
    ASH_STANDALONE=1 "$DAEMON" \
        --socket "$SOCKET" \
        --apk-socket "$APK_SOCKET" \
        --deny-list "$DENY_LIST" \
        --cache "$CACHE" \
        --config "$PERSISTENT_DIR/config" &
    DAEMON_PID_VAL=$!
    echo "$DAEMON_PID_VAL" > "$DAEMON_PID"

    # Give it time to bind the socket
    sleep 1

    if [ -S "$SOCKET" ]; then
        echo "[ksu-toast] Daemon started (pid: $DAEMON_PID_VAL)"
    else
        echo "[ksu-toast] Daemon failed to start — socket not created"
        # Retry once after a short delay
        sleep 2
        if [ -x "$DAEMON" ]; then
            ASH_STANDALONE=1 "$DAEMON" \
                --socket "$SOCKET" \
                --apk-socket "$APK_SOCKET" \
                --deny-list "$DENY_LIST" \
                --cache "$CACHE" \
                --config "$PERSISTENT_DIR/config" &
            echo $! > "$DAEMON_PID"
            sleep 1
            if [ -S "$SOCKET" ]; then
                echo "[ksu-toast] Daemon started on retry"
            else
                echo "[ksu-toast] Daemon failed to start after retry"
            fi
        fi
    fi
else
    echo "[ksu-toast] Daemon binary not found at $DAEMON"
fi

# 3. Start companion APK foreground service (no root needed)
if pm path com.wildkernels.ksutoast >/dev/null 2>&1; then
    am start-foreground-service -n com.wildkernels.ksutoast/.MainService >/dev/null 2>&1 && \
        echo "[ksu-toast] Companion APK service started" || \
        echo "[ksu-toast] Failed to start APK service"
fi

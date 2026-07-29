#!/system/bin/sh

# KSU Toast - boot-completed.sh
# Runs after system is fully booted.
# Daemon binary lives at /system/bin/ksu-toastd (mounted by KSU overlay).

MODDIR=/data/adb/modules/ksu_toast
PERSISTENT_DIR=/data/adb/ksu-toast
SOCKET="$PERSISTENT_DIR/daemon.sock"
APK_SOCKET="/data/adb/ksu-toast/apk.sock"
DENY_LIST="$PERSISTENT_DIR/deny.list"
CACHE="$PERSISTENT_DIR/allow.cache"
# Daemon at system overlay path — guaranteed accessible by KSU mount
DAEMON=/system/bin/ksu-toastd
DAEMON_PID="$PERSISTENT_DIR/daemon.pid"
LOG="$PERSISTENT_DIR/daemon.log"

mkdir -p "$PERSISTENT_DIR"

# 1. Install companion APK if needed, and auto-grant notification perms
if ! pm path com.wildkernels.ksutoast >/dev/null 2>&1; then
    if [ -f "$MODDIR/apk/KsuToast.apk" ]; then
        cp "$MODDIR/apk/KsuToast.apk" /data/local/tmp/KsuToast.apk
        pm install -r /data/local/tmp/KsuToast.apk 2>&1 </dev/null | grep -v "^\s*$"
        rm -f /data/local/tmp/KsuToast.apk
    fi
fi

# Grant permissions — runs as root, no user prompt needed
pm grant com.wildkernels.ksutoast android.permission.POST_NOTIFICATIONS 2>/dev/null || true
pm grant com.wildkernels.ksutoast android.permission.SYSTEM_ALERT_WINDOW 2>/dev/null || true

# 2. Start daemon if not already running
if [ -f "$DAEMON_PID" ]; then
    PID=$(cat "$DAEMON_PID" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "[ksu-toast] Daemon already running (pid: $PID)"
        am start-foreground-service -n com.wildkernels.ksutoast/.MainService >/dev/null 2>&1 || true
        exit 0
    fi
fi

rm -f "$SOCKET" "$DAEMON_PID"
# APK socket is abstract (\0ksu-toast-apk) — no filesystem file to remove
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

    # Fix SELinux context on APK socket so the companion app can connect
    chcon u:object_r:app_data_file:s0 "$APK_SOCKET" 2>/dev/null || true

    if [ -S "$SOCKET" ]; then
        echo "[ksu-toast] Daemon started (pid: $(cat $DAEMON_PID))"
    else
        echo "[ksu-toast] Daemon failed to start — check $LOG"
        ls -la "$DAEMON" >> "$LOG" 2>&1
    fi
else
    echo "[ksu-toast] Daemon not found at $DAEMON"
    ls -la /system/bin/ksu-toastd >> "$LOG" 2>&1 || true
    ls -la "$MODDIR/system/bin/ksu-toastd" >> "$LOG" 2>&1 || true
fi

# 3. Start companion APK foreground service via launcher activity.
# FLAG_ACTIVITY_NEW_TASK (0x10000000) required for starting
# activities from shell context. Also fall back to direct
# start-foreground-service in case activity approach fails.
if pm path com.wildkernels.ksutoast >/dev/null 2>&1; then
    am start -n com.wildkernels.ksutoast/.LauncherActivity -f 0x10000000 >/dev/null 2>&1 || \
    am start-foreground-service -n com.wildkernels.ksutoast/.MainService >/dev/null 2>&1 || true
fi

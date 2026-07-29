#!/system/bin/sh
# KSU Toast - Action button script
# Shows everything: status → test → logs.
# Logs are catted AFTER the test so they include new entries.

MODDIR=${0%/*}
PERSISTENT_DIR=/data/adb/ksu-toast
SOCKET="$PERSISTENT_DIR/daemon.sock"
DAEMON_LOG="$PERSISTENT_DIR/daemon.log"
APK_STATUS="/data/data/com.wildkernels.ksutoast/files/ksu-toast-apk-status.txt"

echo "╔══════════════════════════════════╗"
echo "║        KSU Toast                 ║"
echo "╚══════════════════════════════════╝"

# ── 1. Status ─────────────────────────────────────────────
echo ""
echo "═══ Status ═══"

DAEMON_PID="$PERSISTENT_DIR/daemon.pid"
if [ -f "$DAEMON_PID" ]; then
    PID=$(cat "$DAEMON_PID" 2>/dev/null)
    kill -0 "$PID" 2>/dev/null && echo "DAEMON: running (pid $PID)" || echo "DAEMON: pid file stale"
else
    echo "DAEMON: not started"
fi

[ -S "$SOCKET" ] && echo "SOCKET: ready" || echo "SOCKET: missing"
[ -f "$PERSISTENT_DIR/deny.list" ] && echo "DENY LIST: $(wc -l < "$PERSISTENT_DIR/deny.list") entries"
[ -f "$PERSISTENT_DIR/allow.cache" ] && echo "ALLOW CACHE: $(wc -l < "$PERSISTENT_DIR/allow.cache") entries"
file /system/bin/su 2>/dev/null | grep -q ELF && echo "SU WRAPPER: active (binary)" || echo "SU WRAPPER: symlink only"
pm path com.wildkernels.ksutoast >/dev/null 2>&1 && echo "APK: installed" || echo "APK: not installed"

# ── 2. Test ───────────────────────────────────────────────
echo ""
echo "═══ Test: simulate root request ═══"

if [ -S "$SOCKET" ]; then
    # Start APK service (in case not already running)
    am start -n com.wildkernels.ksutoast/.LauncherActivity -f 0x10000000 >/dev/null 2>&1 || \
    am start-foreground-service -n com.wildkernels.ksutoast/.MainService >/dev/null 2>&1 || true

    echo "Sending CHECK 99999 TestApp to daemon..."
    echo ""

    REQ="CHECK 99999 TestApp"
    RESULT=""

    [ -z "$RESULT" ] && [ -x /system/bin/sock-test ] && \
        RESULT=$(/system/bin/sock-test "$SOCKET" "$REQ" 2>/dev/null) || true
    [ -z "$RESULT" ] && \
        RESULT=$(echo "$REQ" | /data/adb/ksu/bin/busybox nc -U -w 3 "$SOCKET" 2>/dev/null </dev/null) || true
    [ -z "$RESULT" ] && command -v socat >/dev/null 2>&1 && \
        RESULT=$(echo "$REQ" | socat UNIX-CONNECT:"$SOCKET" - 2>/dev/null) || true
    [ -z "$RESULT" ] && command -v python3 >/dev/null 2>&1 && \
        RESULT=$(python3 -c "
import socket
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
s.settimeout(5)
s.connect('$SOCKET')
s.send(b'$REQ\n')
r=s.recv(256)
s.close()
print(r.decode().strip())
" 2>/dev/null) || true

    case "$RESULT" in
        ALLOWED) echo "→ DAEMON SAYS: ALLOWED (would grant root)" ;;
        DENIED)  echo "→ DAEMON SAYS: DENIED (APK not connected or timed out)" ;;
        *)       [ -n "$RESULT" ] && echo "→ DAEMON SAYS: $RESULT"
                 [ -z "$RESULT" ] && echo "→ Could not reach daemon (no socket tool)"
                 ;;
    esac
else
    echo "Daemon socket missing — testing su-wrapper directly."
    TEST_OUTPUT=$(su -c id 2>&1 </dev/null) && \
        echo "→ su works (uid=$(echo "$TEST_OUTPUT" | grep -o 'uid=[^ ]*' || echo "root"))" || \
        echo "→ su failed"
fi

# ── 3. Daemon log (catted after test — includes test results) ───
echo ""
echo "═══ Daemon log ═══"
if [ -f "$DAEMON_LOG" ]; then
    cat "$DAEMON_LOG" 2>/dev/null || echo "(empty)"
else
    echo "(no log)"
fi

# ── 4. APK connection status (catted after test) ────────────
echo ""
echo "═══ APK connection status ═══"
if [ -f "$APK_STATUS" ]; then
    cat "$APK_STATUS" 2>/dev/null
else
    echo "(no status file — APK service may not have started)"
fi

echo ""
echo "═══ End ═══"
echo "Logs: $DAEMON_LOG | $APK_STATUS"

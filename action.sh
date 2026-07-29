#!/system/bin/sh
# KSU Toast - Action button script
# Runs when you tap the "Action" button in KSU Next Manager.
# Shows status + optionally triggers a test root request.

MODDIR=${0%/*}
PERSISTENT_DIR=/data/adb/ksu-toast

echo "╔══════════════════════════════════╗"
echo "║        KSU Toast                 ║"
echo "╚══════════════════════════════════╝"
echo ""

# ── Status checks ────────────────────────────────────────
DAEMON_PID="$PERSISTENT_DIR/daemon.pid"
if [ -f "$DAEMON_PID" ]; then
    PID=$(cat "$DAEMON_PID" 2>/dev/null)
    if kill -0 "$PID" 2>/dev/null; then
        echo "✓ Daemon running (pid: $PID)"
    else
        echo "✗ Daemon pid file stale"
    fi
else
    echo "✗ Daemon not started"
fi

if [ -S "$PERSISTENT_DIR/daemon.sock" ]; then
    echo "✓ Daemon socket ready"
else
    echo "✗ Daemon socket missing"
fi

# Show last few lines of daemon log if something's wrong
if [ ! -S "$PERSISTENT_DIR/daemon.sock" ] && [ -f "$PERSISTENT_DIR/daemon.log" ]; then
    echo ""
    echo "═══ Daemon log (last 5 lines) ═══"
    tail -5 "$PERSISTENT_DIR/daemon.log" 2>/dev/null
    echo ""
fi

DENY="$PERSISTENT_DIR/deny.list"
[ -f "$DENY" ] && echo "✓ Deny list: $(wc -l < "$DENY") entries" || echo "✗ Deny list missing"

CACHE="$PERSISTENT_DIR/allow.cache"
[ -f "$CACHE" ] && echo "✓ Allow cache: $(wc -l < "$CACHE") entries" || echo "✗ Allow cache missing"

if [ -f /system/bin/su ] && file /system/bin/su 2>/dev/null | grep -q ELF; then
    echo "✓ su wrapper active (binary)"
else
    echo "? su is symlink — wrapper may not be active"
fi

if pm path com.wildkernels.ksutoast >/dev/null 2>&1; then
    echo "✓ Companion APK installed"
else
    echo "✗ Companion APK not installed"
fi

echo ""
echo "═══ Test: trigger root request ═══"
echo ""

SOCKET="$PERSISTENT_DIR/daemon.sock"
BUSYBOX=/data/adb/ksu/bin/busybox

if [ -S "$SOCKET" ]; then
    # Send a fake CHECK with UID 99999 (not in any list) to trigger
    # the full daemon → APK → notification flow, exactly as if a
    # real unknown app requested root. No actual root is granted.
    echo "Sending test request to daemon (UID 99999, app TestApp)..."
    echo ""
    TEST_RESULT=$(echo "CHECK 99999 TestApp" | $BUSYBOX nc -U -w 3 "$SOCKET" 2>&1 </dev/null) || true
    if echo "$TEST_RESULT" | grep -q "ALLOWED"; then
        echo "✓ Daemon responded: ROOT GRANTED (would be allowed)"
    elif echo "$TEST_RESULT" | grep -q "DENIED"; then
        echo "⚠ Daemon responded: DENIED (check APK notification)"
        echo "  (A notification should appear within 10 seconds)"
    else
        echo "⚠ Daemon response: $TEST_RESULT"
        echo "  (Notification may already be showing)"
    fi
else
    # Fallback: direct su test
    echo "Daemon socket not available — testing su-wrapper directly."
    echo ""
    TEST_OUTPUT=$(su -c id 2>&1 </dev/null) && {
        echo "✓ ROOT ACCESS GRANTED via ksud (direct path)"
        echo "  uid=$(echo "$TEST_OUTPUT" | grep -o 'uid=[^ ]*' || echo "unknown")"
    } || {
        echo "✗ Root request denied"
    }
fi

echo ""
echo "═══ Help ═══"
echo ""
echo "- Ensure daemon is running: check status above"
echo "- Grant notification permission to KSU Toast app"
echo "- Check /data/adb/ksu-toast/ for logs"
echo ""

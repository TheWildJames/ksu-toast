#!/system/bin/sh
# KSU Toast - Action button script
# Runs when you tap the "Action" button in KSU Next Manager.
# Just a status check — doesn't modify anything.

MODDIR=${0%/*}

echo "╔══════════════════════════════════╗"
echo "║        KSU Toast v1             ║"
echo "╚══════════════════════════════════╝"
echo ""

# Check daemon status
DAEMON_PID=/data/adb/ksu-toast/daemon.pid
if [ -f "$DAEMON_PID" ]; then
    PID=$(cat "$DAEMON_PID" 2>/dev/null)
    if kill -0 "$PID" 2>/dev/null; then
        echo "✓ Daemon running (pid: $PID)"
    else
        echo "✗ Daemon pid file stale — not running"
    fi
else
    echo "✗ Daemon not started"
fi

# Check socket
if [ -S /data/adb/ksu-toast/daemon.sock ]; then
    echo "✓ Socket exists"
else
    echo "✗ Socket missing"
fi

# Check deny list count
DENY=/data/adb/ksu-toast/deny.list
if [ -f "$DENY" ]; then
    COUNT=$(wc -l < "$DENY")
    echo "✓ Deny list: $COUNT entries"
else
    echo "✗ Deny list missing"
fi

# Check cache count
CACHE=/data/adb/ksu-toast/allow.cache
if [ -f "$CACHE" ]; then
    COUNT=$(wc -l < "$CACHE")
    echo "✓ Allow cache: $COUNT entries"
else
    echo "✗ Allow cache missing"
fi

# Check su wrapper
if [ -f /system/bin/su ]; then
    SU_TYPE=$(file /system/bin/su 2>/dev/null | grep -c "ELF" || echo 0)
    if [ "$SU_TYPE" -ge 1 ]; then
        echo "✓ su wrapper installed (binary)"
    else
        echo "? su is symlink — wrapper may not be active"
    fi
else
    echo "✗ su binary missing"
fi

# Check companion APK
APK_INFO=$(pm list packages com.wildkernels.ksutoast 2>/dev/null)
if echo "$APK_INFO" | grep -q "ksutoast"; then
    echo "✓ Companion APK installed"
else
    echo "? Companion APK not installed"
fi

echo ""
echo "To see this again: tap Action in KSU Manager"
echo ""

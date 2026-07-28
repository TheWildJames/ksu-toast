#!/system/bin/sh

# KSU Toast - post-fs-data.sh
# Early boot — just set up props. Daemon and APK handled
# in boot-completed.sh where system is fully ready.

mkdir -p /data/adb/ksu-toast/config
setprop ksu.toast.timeout 10

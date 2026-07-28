# KSU Toast - Top-level Makefile for local builds
# Requires Android NDK installed. Set NDK_PATH or ANDROID_NDK_HOME.

NDK_PATH ?= $(ANDROID_NDK_HOME)
TOOLCHAIN ?= $(NDK_PATH)/toolchains/llvm/prebuilt/linux-x86_64
CC ?= $(TOOLCHAIN)/bin/aarch64-linux-android33-clang
VERSION ?= 1
MODULE_ID = ksu_toast

BUILD_DIR = build
DIST_DIR = dist

.PHONY: all clean wrapper daemon apk module zip release

all: module

# ── Android NDK check ────────────────────────────────────
check-ndk:
	@if [ ! -x "$(CC)" ]; then \
		echo "ERROR: ARM64 clang not found at $(CC)"; \
		echo "Set NDK_PATH or ANDROID_NDK_HOME to your NDK installation."; \
		exit 1; \
	fi

# ── Build C binaries ─────────────────────────────────────
wrapper: check-ndk
	mkdir -p $(BUILD_DIR)/system/bin
	$(CC) -static -Os -s -Wall -Wextra -o $(BUILD_DIR)/system/bin/su wrapper/su-wrapper.c
	@echo "  → $(BUILD_DIR)/system/bin/su"
	@file $(BUILD_DIR)/system/bin/su

daemon: check-ndk
	mkdir -p $(BUILD_DIR)/system/bin
	$(CC) -static -Os -s -Wall -Wextra -pthread -o $(BUILD_DIR)/system/bin/ksu-toastd daemon/ksu-toastd.c
	@echo "  → $(BUILD_DIR)/system/bin/ksu-toastd"
	@file $(BUILD_DIR)/system/bin/ksu-toastd

# ── Build APK ────────────────────────────────────────────
apk:
	cd apk && ./gradlew assembleRelease --no-daemon
	mkdir -p $(BUILD_DIR)/apk
	cp apk/app/build/outputs/apk/release/app-release.apk $(BUILD_DIR)/apk/KsuToast.apk 2>/dev/null || \
		cp apk/app/build/outputs/apk/release/app-release-unsigned.apk $(BUILD_DIR)/apk/KsuToast.apk 2>/dev/null || \
		echo "WARNING: APK build failed"
	@echo "  → $(BUILD_DIR)/apk/KsuToast.apk"

# ── Assemble KSU module ──────────────────────────────────
module: wrapper daemon apk
	# Copy module scripts
	cp module.prop $(BUILD_DIR)/
	cp customize.sh $(BUILD_DIR)/
	cp post-fs-data.sh $(BUILD_DIR)/
	cp service.sh $(BUILD_DIR)/
	cp boot-completed.sh $(BUILD_DIR)/
	cp action.sh $(BUILD_DIR)/
	cp sepolicy.rule $(BUILD_DIR)/

	# Generate final module.prop with version
	sed -i "s/^version=.*/version=v$(VERSION)/" $(BUILD_DIR)/module.prop
	sed -i "s/^versionCode=.*/versionCode=$(VERSION)/" $(BUILD_DIR)/module.prop
	@echo "  → Module assembled in $(BUILD_DIR)/"

# ── Create distributable zip ──────────────────────────────
zip: module
	mkdir -p $(DIST_DIR)
	cd $(BUILD_DIR) && zip -r9 "../$(DIST_DIR)/$(MODULE_ID)-v$(VERSION).zip" .
	@echo "  → $(DIST_DIR)/$(MODULE_ID)-v$(VERSION).zip"

release: zip
	@echo "Build complete: $(DIST_DIR)/$(MODULE_ID)-v$(VERSION).zip"

# ── Clean ─────────────────────────────────────────────────
clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR)
	cd wrapper && $(MAKE) clean 2>/dev/null || true
	cd daemon && $(MAKE) clean 2>/dev/null || true
	@echo "Cleaned"

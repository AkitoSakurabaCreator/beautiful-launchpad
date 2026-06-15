#!/usr/bin/env bash
#
# Builds the Launchpad executable with SwiftPM and assembles a runnable
# macOS .app bundle (no full Xcode required — Command Line Tools are enough).
#
set -euo pipefail

APP_NAME="Launchpad"               # SwiftPM product / executable (matches Package.swift target & CFBundleExecutable)
BUNDLE_NAME="Beautiful Launchpad"  # user-facing .app bundle file name (Finder / Dock)
CONFIG="${1:-release}"   # pass "debug" for a faster build
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "error: built binary not found at $BIN_PATH" >&2
    exit 1
fi

APP_DIR="$SCRIPT_DIR/$BUNDLE_NAME.app"
echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

# App icon. Prefer a source `icon.png` (converted to .icns here, so the repo only
# needs to keep the PNG); otherwise fall back to a pre-made AppIcon.icns.
ICNS_OUT="$APP_DIR/Contents/Resources/AppIcon.icns"
if [[ -f "$SCRIPT_DIR/icon.png" ]]; then
    echo "==> generating AppIcon.icns from icon.png"
    ICONSET_PARENT="$(mktemp -d)"
    ICONSET="$ICONSET_PARENT/AppIcon.iconset"
    mkdir -p "$ICONSET"
    # size:name pairs for the standard macOS iconset (1x + @2x).
    for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x \
                128:128x128 256:128x128@2x 256:256x256 512:256x256@2x \
                512:512x512 1024:512x512@2x; do
        px="${spec%%:*}"; name="${spec##*:}"
        sips -z "$px" "$px" "$SCRIPT_DIR/icon.png" --out "$ICONSET/icon_${name}.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$ICNS_OUT"
    rm -rf "$ICONSET_PARENT"
elif [[ -f "$SCRIPT_DIR/AppIcon.icns" ]]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$ICNS_OUT"
fi

# --- Embed Sparkle.framework (auto-update) ------------------------------------
# SwiftPM copies Sparkle.framework next to the built binary; move it into the
# bundle's Frameworks dir and make sure the executable can find it via @rpath.
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
SPARKLE_FW="$(swift build -c "$CONFIG" --show-bin-path)/Sparkle.framework"
SPARKLE_EMBED="$FRAMEWORKS_DIR/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
    echo "==> embedding Sparkle.framework"
    mkdir -p "$FRAMEWORKS_DIR"
    # ditto preserves the framework's Versions/symlink layout (and signatures).
    ditto "$SPARKLE_FW" "$SPARKLE_EMBED"

    # The executable links Sparkle via @rpath; ensure Contents/Frameworks is searched.
    EXE="$APP_DIR/Contents/MacOS/$APP_NAME"
    if ! otool -l "$EXE" | grep -q "@executable_path/../Frameworks"; then
        install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXE"
    fi
else
    echo "warning: Sparkle.framework not found at $SPARKLE_FW"
    echo "         (auto-update will be unavailable in this build)"
fi

# --- Ad-hoc code signing (inside-out) -----------------------------------------
# Ad-hoc signature so the app launches locally without Gatekeeper friction.
# Sign Sparkle's nested helpers (XPC services, Autoupdate, Updater.app) FIRST,
# then the framework, then the whole app. We deliberately avoid `--deep` on the
# outer sign so it does not re-sign (and mis-sign) the nested Sparkle code.
echo "==> ad-hoc code signing (inside-out)"
if [[ -d "$SPARKLE_EMBED" ]]; then
    VER_DIR="$SPARKLE_EMBED/Versions/Current"
    for item in \
        "$VER_DIR/XPCServices/Downloader.xpc" \
        "$VER_DIR/XPCServices/Installer.xpc" \
        "$VER_DIR/Autoupdate" \
        "$VER_DIR/Updater.app"; do
        if [[ -e "$item" ]]; then
            codesign --force --sign - "$item" >/dev/null 2>&1 || \
                echo "warning: codesign failed for $item"
        fi
    done
    codesign --force --sign - "$SPARKLE_EMBED" >/dev/null 2>&1 || \
        echo "warning: codesign failed for Sparkle.framework"
fi
codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || \
    echo "warning: codesign skipped/failed (app should still run locally)"

echo ""
echo "Built: $APP_DIR"
echo "Run:   open \"$APP_DIR\"    (or double-click it in Finder)"

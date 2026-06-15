#!/usr/bin/env bash
#
# Builds the Launchpad executable with SwiftPM and assembles a runnable
# macOS .app bundle (no full Xcode required — Command Line Tools are enough).
#
set -euo pipefail

APP_NAME="Launchpad"
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

APP_DIR="$SCRIPT_DIR/$APP_NAME.app"
echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

# Optional custom icon: drop an AppIcon.icns next to this script to embed it.
if [[ -f "$SCRIPT_DIR/AppIcon.icns" ]]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc code signature so the app launches locally without Gatekeeper friction.
echo "==> ad-hoc code signing"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || \
    echo "warning: codesign skipped/failed (app should still run locally)"

echo ""
echo "Built: $APP_DIR"
echo "Run:   open \"$APP_DIR\"    (or double-click it in Finder)"

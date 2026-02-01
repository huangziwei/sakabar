#!/bin/sh
set -euo pipefail

APP_NAME="sakabar"
BUNDLE_ID="com.sakabar.app"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE="$BUILD_DIR/module-cache"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE"

swiftc -O \
  -module-cache-path "$MODULE_CACHE" \
  -framework AppKit \
  -framework Foundation \
  -framework ServiceManagement \
  "$ROOT_DIR/Sources"/*.swift \
  -o "$MACOS_DIR/$APP_NAME"

cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS_DIR/Info.plist" >/dev/null 2>&1 || true

printf "Built %s\n" "$APP_DIR"

#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

DISPLAY_NAME="Clever Music Player"
VERSION="0.2.0"

BUILD_DIR="build/macos/Build/Products/Release"
APP_BUNDLE="$DISPLAY_NAME.app"
APP_PATH="$BUILD_DIR/$APP_BUNDLE"

DIST_DIR="dist/macos"
DMG_NAME="${DISPLAY_NAME// /}_macOS_${VERSION}.dmg"

STAGE_DIR="$DIST_DIR/dmg_stage"
RW_DMG="$DIST_DIR/${DISPLAY_NAME// /}_rw.dmg"
FINAL_DMG="$DIST_DIR/$DMG_NAME"
MOUNT_DIR="$PWD/$DIST_DIR/dmg_mount"

cleanup_mount() {
  hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 ||
    hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 ||
    true

  for _ in 1 2 3 4 5; do
    if ! mount | grep -Fq " on $MOUNT_DIR "; then
      return
    fi
    sleep 0.2
  done
}

echo "==> Building macOS release"
flutter build macos --release

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found: $APP_PATH"
  echo "Available apps:"
  find "$BUILD_DIR" -maxdepth 1 -name "*.app" -print || true
  exit 1
fi

echo "==> Preparing stage directory"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

cp -R "$APP_PATH" "$STAGE_DIR/$DISPLAY_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

mkdir -p "$DIST_DIR"
cleanup_mount
rm -rf "$MOUNT_DIR"
rm -f "$RW_DMG" "$FINAL_DMG"

echo "==> Creating temporary writable DMG"
hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDRW \
  "$RW_DMG"

echo "==> Applying Finder layout"
mkdir -p "$MOUNT_DIR"
hdiutil attach "$RW_DMG" \
  -readwrite \
  -noverify \
  -noautoopen \
  -mountpoint "$MOUNT_DIR" \
  >/dev/null

trap cleanup_mount EXIT

osascript <<OSA
tell application "Finder"
  set dmgFolder to POSIX file "$MOUNT_DIR" as alias
  open dmgFolder
  set current view of container window of dmgFolder to icon view
  set toolbar visible of container window of dmgFolder to false
  set statusbar visible of container window of dmgFolder to false
  set bounds of container window of dmgFolder to {200, 120, 740, 430}
  set viewOptions to the icon view options of container window of dmgFolder
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 96
  set position of item "$APP_BUNDLE" of dmgFolder to {155, 160}
  set position of item "Applications" of dmgFolder to {385, 160}
  update dmgFolder without registering applications
  delay 1
  close container window of dmgFolder
end tell
OSA

sync
cleanup_mount
trap - EXIT
rm -rf "$MOUNT_DIR"

echo "==> Converting to compressed DMG"
hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$FINAL_DMG"

rm -f "$RW_DMG"

echo "==> Done:"
echo "$FINAL_DMG"

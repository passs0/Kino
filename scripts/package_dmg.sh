#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Serein"
VERSION="0.1.6"
DMG_NAME="Serein-v${VERSION}-macOS.dmg"
STAGING_DIR="/tmp/serein_dmg_staging"
RW_DMG="/tmp/serein_rw.dmg"

echo "🧹 Cleaning previous staging..."
rm -rf "$STAGING_DIR" "$RW_DMG" "$DMG_NAME"
mkdir -p "$STAGING_DIR"

echo "📦 Preparing staging files..."
cp -R "build/$APP_NAME.app" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "💿 Creating temporary read-write disk image..."
hdiutil create -srcfolder "$STAGING_DIR" -volname "$APP_NAME" -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW "$RW_DMG" -ov

echo "🔌 Mounting read-write disk image..."
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | grep "/Volumes/$APP_NAME" | awk '{print $3}')

if [ -z "$MOUNT_DIR" ]; then
    echo "❌ Failed to mount read-write disk image."
    exit 1
fi

echo "Mounted at: $MOUNT_DIR"

echo "🎨 Customizing Finder presentation..."
osascript << APPLESCRIPT || true
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 200, 940, 560}
        set theViewOptions to the icon view options of container window
        set icon size of theViewOptions to 100
        set arrangement of theViewOptions to not arranged
        set position of item "$APP_NAME.app" of container window to {140, 170}
        set position of item "Applications" of container window to {400, 170}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Give Finder a moment to commit .DS_Store
sync
sleep 2

echo "⏏️ Ejecting disk image..."
diskutil eject "$MOUNT_DIR" || hdiutil detach "$MOUNT_DIR" -force

echo "🗜️ Converting to compressed, read-only DMG ($DMG_NAME)..."
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_NAME" -ov

echo "🔐 Ad-hoc codesigning disk image..."
codesign --force --sign - "$DMG_NAME"

echo "🧹 Cleaning up temporary files..."
rm -rf "$STAGING_DIR" "$RW_DMG"

echo "✨ Disk image successfully created: $DMG_NAME"
ls -lh "$DMG_NAME"

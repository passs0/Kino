#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Serein"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE="/tmp/swift-cache"

echo "🔨 Building $APP_NAME for macOS..."

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE"

SDK_PATH="$(xcrun --show-sdk-path)"

# Collect all swift sources
SWIFT_FILES=()
while IFS= read -r file; do
    SWIFT_FILES+=("$file")
done < <(find Sources/Serein -name "*.swift")

echo "📦 Compiling ${#SWIFT_FILES[@]} Swift source files..."
swiftc \
    -target arm64-apple-macos26.0 \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -O \
    "${SWIFT_FILES[@]}" \
    -o "$MACOS_DIR/$APP_NAME"

# Clean compiler cache to keep system lean
rm -rf "$MODULE_CACHE"

# Strip unneeded local debug symbols and symbol tables before signing
strip -rSTx "$MACOS_DIR/$APP_NAME"

echo "📄 Copying Info.plist and AppIcon.icns..."
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Build Companion Safari Web Extension
EXT_NAME="Serein Safari Extension"
PLUGINS_DIR="$CONTENTS_DIR/PlugIns"
EXT_BUNDLE="$PLUGINS_DIR/$EXT_NAME.appex"
EXT_CONTENTS="$EXT_BUNDLE/Contents"
EXT_MACOS="$EXT_CONTENTS/MacOS"
EXT_RESOURCES="$EXT_CONTENTS/Resources"

echo "🧩 Building companion Safari Extension ($EXT_NAME)..."
rm -rf "$EXT_BUNDLE"
mkdir -p "$EXT_MACOS" "$EXT_RESOURCES"

swiftc \
    -target arm64-apple-macos26.0 \
    -sdk "$SDK_PATH" \
    -O \
    SafariExtension/SafariWebExtensionHandler.swift \
    -o "$EXT_MACOS/$EXT_NAME"

strip -rSTx "$EXT_MACOS/$EXT_NAME"

cp "SafariExtension/Info.plist" "$EXT_CONTENTS/Info.plist"
cp -R SafariExtension/Resources/* "$EXT_RESOURCES/"

echo "🔐 Ad-hoc code signing $EXT_NAME.appex..."
codesign --force --sign - --entitlements SafariExtension/Extension.entitlements "$EXT_BUNDLE"

# Clear quarantine and extended attributes
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

echo "🔐 Ad-hoc code signing $APP_NAME.app..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✅ Successfully built $APP_BUNDLE"
ls -ld "$APP_BUNDLE"

echo "🚀 Installing cleanly to /Applications/$APP_NAME.app..."
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"

# Register URL scheme and PlugIn with LaunchServices
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP_NAME.app" 2>/dev/null || true
pluginkit -a "/Applications/$APP_NAME.app/Contents/PlugIns/$EXT_NAME.appex" 2>/dev/null || true
echo "✨ Installed and registered to /Applications/$APP_NAME.app"

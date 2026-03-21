#!/bin/bash
set -euo pipefail

# PasteFlow DMG builder
# Usage: ./scripts/create-dmg.sh
#
# Prerequisites:
#   brew install create-dmg
#
# Background image: assets/dmg-background@2x.png (1320x840, retina)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="PasteFlow"
BUILD_DIR="$PROJECT_DIR/build"
DMG_DIR="$BUILD_DIR/dmg"
OUTPUT_DIR="$BUILD_DIR"

# Clean previous build
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Build the app in Release mode
echo "==> Building $APP_NAME (Release)..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -project "$PROJECT_DIR/PasteFlow.xcodeproj" \
    -scheme PasteFlow \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    build

# Find the built .app
APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH not found"
    exit 1
fi

# Copy app to staging area
cp -R "$APP_PATH" "$DMG_DIR/"

# Get version from Info.plist
VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

# Remove existing DMG
rm -f "$DMG_PATH"

echo "==> Creating DMG: $DMG_NAME..."

# Build create-dmg command
CREATE_DMG_ARGS=(
    --volname "$APP_NAME"
    --volicon "$PROJECT_DIR/assets/VolumeIcon.icns"
    --window-pos 200 120
    --window-size 660 448
    --icon-size 128
    --text-size 12
    --icon "$APP_NAME.app" 190 172
    --hide-extension "$APP_NAME.app"
    --app-drop-link 470 172
)

# Add retina background image if it exists
BG_IMAGE="$PROJECT_DIR/assets/dmg-background@2x.png"
if [ -f "$BG_IMAGE" ]; then
    CREATE_DMG_ARGS+=(--background "$BG_IMAGE")
    echo "    Using background: $BG_IMAGE"
else
    echo "    Warning: No background found at assets/dmg-background@2x.png"
fi

create-dmg "${CREATE_DMG_ARGS[@]}" "$DMG_PATH" "$DMG_DIR/"

echo ""
echo "==> Done! DMG created at:"
echo "    $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"

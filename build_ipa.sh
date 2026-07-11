#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG="Debug"
ARCH="arm64"
APP_NAME="TrollStoreDarkSword"

echo "==> Regenerating Xcode project"
xcodegen

echo "==> Building"
xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration "$CONFIG" \
    -arch "$ARCH" \
    -sdk iphoneos \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="-" \
    build

APP_PATH=$(find "$SCRIPT_DIR/build" -name "$APP_NAME.app" -type d | head -n1)
[ -z "$APP_PATH" ] && { echo "ERROR: .app not found"; exit 1; }

echo "==> Packaging IPA"
STAGING=$(mktemp -d)
PAYLOAD="$STAGING/Payload"
mkdir -p "$PAYLOAD"
cp -R "$APP_PATH" "$PAYLOAD/$APP_NAME.app"

IPA_NAME="$APP_NAME.ipa"
rm -f "$SCRIPT_DIR/build/$IPA_NAME"
(cd "$STAGING" && zip -qr "$SCRIPT_DIR/build/$IPA_NAME" Payload)
rm -rf "$STAGING"
echo "==> build/$IPA_NAME"

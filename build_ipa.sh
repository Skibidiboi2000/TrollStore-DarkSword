#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="TrollStoreDarkSword"
SCHEME="$PROJECT_NAME"
OUTPUT_DIR="$PROJECT_DIR/build"

echo "=== TrollStoreDarkSword IPA Builder ==="

# 1. Check Xcode
if ! xcodebuild -version &>/dev/null; then
    echo "ERROR: Xcode is required but not found."
    echo "Install from the Mac App Store or https://developer.apple.com/xcode/"
    echo "After installing, run: sudo xcode-select -switch /Applications/Xcode.app"
    exit 1
fi

# 2. Check XcodeGen
if ! which xcodegen &>/dev/null; then
    echo "Installing XcodeGen..."
    brew install xcodegen
fi

# 3. Regenerate project
echo "[1/4] Generating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate 2>&1 | sed 's/^/  /'

# 4. Build
echo "[2/4] Building for iOS arm64 + arm64e..."
cd "$PROJECT_DIR"
xcodebuild \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -configuration Release \
    -derivedDataPath "$OUTPUT_DIR/DerivedData" \
    build 2>&1 | sed 's/^/  /'

APP_PATH=$(find "$OUTPUT_DIR/DerivedData" -name "*.app" -type d -path "*/Release-iphoneos/*" | head -1)
if [ -z "$APP_PATH" ]; then
    echo "ERROR: .app bundle not found after build"
    exit 1
fi
echo "  App built at: $APP_PATH"

# 5. Package IPA
echo "[3/4] Packaging .ipa..."
mkdir -p "$OUTPUT_DIR/Payload"
cp -R "$APP_PATH" "$OUTPUT_DIR/Payload/"
cd "$OUTPUT_DIR"
zip -qr "$PROJECT_NAME.ipa" Payload/
rm -rf Payload/

echo "[4/4] Done!"
echo ""
echo "=== Build Complete ==="
echo "IPA: $OUTPUT_DIR/$PROJECT_NAME.ipa"
echo ""
echo "Next step — sideload with Sideloadly or AltStore:"
echo "  1. Open Sideloadly"
echo "  2. Drag $OUTPUT_DIR/$PROJECT_NAME.ipa into the window"
echo "  3. Enter your Apple ID"
echo "  4. Click Start"
echo ""
echo "Signed in as a standard Apple ID, the app launches via dev cert."
echo "DarkSword exploit at runtime removes trust cache restrictions."

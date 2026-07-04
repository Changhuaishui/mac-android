#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="MacHostApp"
BUILD_DIR=".build/debug"
APP_BUNDLE=".build/${APP_NAME}.app"

echo "Building ${APP_NAME}..."
swift build

echo "Packaging ${APP_NAME}.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.macandroid.${APP_NAME}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
EOF

echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "Signing ${APP_NAME}.app..."
codesign --force --deep --sign - "$APP_BUNDLE"

# 同时输出到 dist/，保持历史约定路径
echo "Copying to dist/${APP_NAME}.app..."
mkdir -p "dist"
rm -rf "dist/${APP_NAME}.app" "dist/${APP_NAME}.zip"
cp -R "$APP_BUNDLE" "dist/${APP_NAME}.app"

echo "Creating dist/${APP_NAME}.zip..."
cd "dist"
zip -rq "${APP_NAME}.zip" "${APP_NAME}.app"
cd "$SCRIPT_DIR"

echo "Done: ${APP_BUNDLE}"
echo "Done: dist/${APP_NAME}.app"
echo "Done: dist/${APP_NAME}.zip"

#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="QuickToggle"
BUILD_DIR="$SCRIPT_DIR/build"
APP="$BUILD_DIR/$APP_NAME.app"
BIN="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

rm -rf "$APP"
mkdir -p "$BIN" "$RES"

echo "→ Debug 编译中..."
/usr/bin/swiftc "$SCRIPT_DIR/QuickToggle.swift" \
  -Onone -g -warnings-as-errors \
  -framework AppKit -framework Carbon -framework ApplicationServices \
  -target "arm64-apple-macosx13.0" \
  -o "$BIN/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>QuickToggle</string>
  <key>CFBundleDisplayName</key><string>轻唤</string>
  <key>CFBundleIdentifier</key><string>com.quicktoggle.app</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>CFBundleShortVersionString</key><string>0.0.2</string>
  <key>CFBundleGetInfoString</key><string>QuickToggle（轻唤）0.0.2</string>
  <key>CFBundleExecutable</key><string>QuickToggle</string>
  <key>CFBundleIconFile</key><string>QuickToggleIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

cp "$SCRIPT_DIR/Assets/QuickToggleIcon-0817v2.icns" "$RES/QuickToggleIcon.icns"

echo "→ 代码签名（ad-hoc）..."
/usr/bin/codesign --force --deep --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"

echo "✓ 构建完成: $APP"
echo "  运行: open \"$APP\""

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"
APP="$SCRIPT_DIR/build/QuickToggle.app"
ZIP="$SCRIPT_DIR/build/QuickToggle-$VERSION-macOS-arm64.zip"

bash "$SCRIPT_DIR/build.sh" --release
/usr/bin/codesign --verify --deep --strict "$APP"

rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo "✓ 打包完成: $ZIP"

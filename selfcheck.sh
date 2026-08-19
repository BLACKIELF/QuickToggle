#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/build/QuickToggle.app"
BIN="$APP/Contents/MacOS/QuickToggle"
TMP="$(mktemp -d)"
PID=""
trap 'if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; fi; rm -rf "$TMP"' EXIT

echo "=== QuickToggle（轻唤）0.0.3 自检 ==="
bash "$DIR/build.sh"
/usr/bin/codesign --verify --deep --strict "$APP"
"$BIN" --self-test
"$BIN" --smoke-test

"$BIN" --idle-measure >"$TMP/idle.log" 2>&1 &
PID=$!
sleep 2
for _ in 1 2 3 4 5; do
  ps -p "$PID" -o %cpu= -o rss= >>"$TMP/samples"
  sleep 1
done

awk '
  { cpu += $1; rss += $2; count += 1 }
  END {
    if (count == 0) exit 1
    printf "空闲 CPU 平均值: %.2f%%\n", cpu / count
    printf "空闲 RSS 平均值: %.0f KB (%.1f MB)\n", rss / count, rss / count / 1024
  }
' "$TMP/samples"

kill "$PID"
wait "$PID" 2>/dev/null || true
PID=""
echo "轻唤自检全部通过"

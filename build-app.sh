#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$ROOT/.build/FreeClip.app}"

cd "$ROOT"
swift build -c release

CONTENTS="$APP/Contents"
mkdir -p "$CONTENTS/MacOS"
cp "$ROOT/.build/release/FreeClip" "$CONTENTS/MacOS/FreeClip"
chmod +x "$CONTENTS/MacOS/FreeClip"
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FreeClip</string>
    <key>CFBundleIdentifier</key>
    <string>org.freeclip.FreeClip2</string>
    <key>CFBundleName</key>
    <string>FreeClip 2</string>
    <key>CFBundleDisplayName</key>
    <string>FreeClip 2</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>连接并读取 FreeClip 2 的设备状态和设置。</string>
</dict>
</plist>
PLIST
codesign --force --deep --sign - \
    --identifier org.freeclip.FreeClip2 \
    --requirements '=designated => identifier "org.freeclip.FreeClip2"' \
    "$APP"
printf 'Built %s\n' "$APP"

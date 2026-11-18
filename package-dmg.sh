#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$ROOT/.build/FreeClip.app}"
OUT_DMG="${2:-$ROOT/.build/FreeClip.dmg}"

if [[ ! -d "$APP" ]]; then
    echo "App bundle not found: $APP" >&2
    exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/FreeClip.app"
ln -s /Applications "$STAGE/Applications"
if [[ -f "$ROOT/Assets/AppIcon.icns" ]]; then
    cp "$ROOT/Assets/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
        SetFile -a C "$STAGE"
    fi
fi

cat > "$STAGE/安装与自签说明.txt" <<'EOF'
FreeClip 2 安装与命令行自签说明
==============================

1. 将 FreeClip.app 拖入旁边的 Applications（应用程序）文件夹。
2. 本应用采用 ad-hoc 签名，未经过 Apple 公证（Notarization）。
   如果首次打开被 macOS 拦截（提示"无法打开"或"已损坏"），请在终端执行：

   xattr -cr /Applications/FreeClip.app
   codesign --force --deep --sign - \
     --identifier org.freeclip.FreeClip2 \
     --requirements '=designated => identifier "org.freeclip.FreeClip2"' \
     /Applications/FreeClip.app

3. 首次运行请在系统弹窗中授予蓝牙权限。
EOF

rm -f "$OUT_DMG"
hdiutil create \
    -volname "FreeClip 2" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$OUT_DMG"

printf 'Packaged %s\n' "$OUT_DMG"

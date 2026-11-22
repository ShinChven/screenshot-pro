#!/bin/bash
# 编译并打包 build/Screenshot Pro.app
#   CONFIG=debug ./scripts/build.sh      调试版本
#   SIGN_ID="证书名" ./scripts/build.sh  用指定证书签名
# 默认使用 scripts/setup-signing.sh 创建的本机证书（重新编译后屏幕录制权限不会失效），
# 没有该证书时退回 ad-hoc 签名。
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
LOCAL_CERT="Screenshot Pro Local Signing"
if [ -z "${SIGN_ID:-}" ]; then
    if security find-certificate -c "$LOCAL_CERT" >/dev/null 2>&1; then
        SIGN_ID="$LOCAL_CERT"
    else
        SIGN_ID="-"
        echo "⚠️  未找到本机签名证书，使用 ad-hoc 签名（每次重新编译都要重新授权屏幕录制）。"
        echo "   执行 ./scripts/setup-signing.sh 可以解决。"
    fi
fi
APP="build/Screenshot Pro.app"

python3 -I scripts/i18n.py
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

if [ ! -f build/AppIcon.icns ]; then
    mkdir -p build
    rm -rf build/AppIcon.iconset
    swift scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ScreenshotPro" "$APP/Contents/MacOS/ScreenshotPro"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"

codesign --force --sign "$SIGN_ID" --identifier com.local.screenshotpro "$APP"
echo "✅ 已生成：$APP（签名：$SIGN_ID）"

#!/bin/bash
# 编译、安装到 /Applications 并启动
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh
pkill -x ScreenshotPro 2>/dev/null || true
sleep 0.5
rm -rf "/Applications/Screenshot Pro.app"
cp -R "build/Screenshot Pro.app" /Applications/
open "/Applications/Screenshot Pro.app"
echo "✅ 已安装到 /Applications/Screenshot Pro.app"
if ! codesign -dr - "/Applications/Screenshot Pro.app" 2>&1 | grep -q "certificate leaf"; then
    echo "   ⚠️ 当前是 ad-hoc 签名，重新编译后需要重新授权屏幕录制。执行 ./scripts/setup-signing.sh 可以解决。"
fi

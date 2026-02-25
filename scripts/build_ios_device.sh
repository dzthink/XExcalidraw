#!/usr/bin/env bash
# iOS 真机构建脚本（使用 xcodebuild）
# 注意：推荐直接使用 ./scripts/build_native.sh ios-deploy

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "========================================"
echo "iOS 真机构建"
echo "========================================"
echo ""

# 检查设备
DEVICE=$(ios-deploy --detect 2>/dev/null | grep "Found" | head -1 || true)
if [ -z "$DEVICE" ]; then
    echo "❌ 未找到连接的设备"
    echo ""
    echo "请确保："
    echo "1. iPhone 已通过 USB 连接"
    echo "2. 设备已解锁"
    echo "3. 在设备上点击了'信任此电脑'"
    exit 1
fi

echo "✅ 发现设备: $DEVICE"
echo ""

# 推荐使用新方式
echo "推荐使用新的构建方式："
echo ""
echo "  ./scripts/build_native.sh ios-deploy"
echo ""
echo "是否使用新方式继续? (Y/n)"
read -r response

if [[ "$response" =~ ^[Nn]$ ]]; then
    echo "使用 Xcode 构建..."
    open "$ROOT_DIR/apps/_legacy_xcode/ExcalidrawIOS.xcodeproj"
    echo "请在 Xcode 中选择设备后点击 Run"
else
    echo "使用新方式构建..."
    "$ROOT_DIR/scripts/build_native.sh" ios-deploy
fi

#!/usr/bin/env bash
# 配置免费开发者账号签名
# 适用于没有付费 Apple Developer 账号的开发者

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_PROJECT="$ROOT_DIR/apps/_legacy_xcode/ExcalidrawIOS.xcodeproj"
MAC_PROJECT="$ROOT_DIR/apps/_legacy_xcode/ExcalidrawMac.xcodeproj"

echo "========================================"
echo "XExcalidraw 免费开发者账号配置"
echo "========================================"
echo ""

# 检查 Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ 错误：未找到 Xcode，请先安装 Xcode"
    exit 1
fi

echo "✅ Xcode 已安装"

# 检查 Apple ID 登录
echo ""
echo "检查开发者账号..."
TEAMS=$(xcrun altool --list-providers 2>/dev/null | grep -E "^\s+[A-Z0-9]+\s+" || true)

if [ -z "$TEAMS" ]; then
    echo ""
    echo "⚠️  未找到开发者账号，请先配置："
    echo ""
    echo "1. 打开 Xcode"
    echo "2. 菜单栏：Xcode → Settings (或 Cmd + ,)"
    echo "3. 选择 Accounts 标签"
    echo "4. 点击左下角 + 按钮"
    echo "5. 选择 'Add Apple ID...'"
    echo "6. 登录你的 Apple ID"
    echo ""
    echo "完成后按回车继续..."
    read
else
    echo "✅ 已配置开发者账号："
    echo "$TEAMS"
fi

# 更新项目 Team ID
echo ""
echo "配置项目签名..."

# 获取第一个 Personal Team ID
TEAM_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed 's/.*(\([A-Z0-9]*\)).*/\1/')

if [ -z "$TEAM_ID" ]; then
    echo "⚠️  未找到签名证书，请在 Xcode 中："
    echo "1. 打开项目: open $IOS_PROJECT"
    echo "2. 选中项目 → Signing & Capabilities"
    echo "3. Team → 选择你的 Apple ID"
    echo "4. 勾选 Automatically manage signing"
    exit 1
fi

echo "✅ 使用 Team ID: $TEAM_ID"

# 更新 Xcode 项目中的 Team ID
if [ -f "$IOS_PROJECT/project.pbxproj" ]; then
    sed -i '' "s/DEVELOPMENT_TEAM = [A-Z0-9]*;/DEVELOPMENT_TEAM = $TEAM_ID;/g" "$IOS_PROJECT/project.pbxproj"
    echo "✅ iOS 项目 Team ID 已更新"
fi

if [ -f "$MAC_PROJECT/project.pbxproj" ]; then
    sed -i '' "s/DEVELOPMENT_TEAM = [A-Z0-9]*;/DEVELOPMENT_TEAM = $TEAM_ID;/g" "$MAC_PROJECT/project.pbxproj"
    echo "✅ macOS 项目 Team ID 已更新"
fi

# 更新构建脚本
echo ""
echo "更新构建脚本配置..."

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/')
if [ -n "$IDENTITY" ]; then
    sed -i '' "s|DEFAULT_IOS_SIGN_IDENTITY=\".*\"|DEFAULT_IOS_SIGN_IDENTITY=\"$IDENTITY\"|" "$ROOT_DIR/scripts/build_native.sh"
    echo "✅ 构建脚本签名配置已更新"
fi

echo ""
echo "========================================"
echo "配置完成！"
echo "========================================"
echo ""
echo "使用方式："
echo ""
echo "1. iOS 模拟器构建："
echo "   ./scripts/build_native.sh ios-app"
echo ""
echo "2. iOS 真机构建（Xcode 方式）："
echo "   open apps/_legacy_xcode/ExcalidrawIOS.xcodeproj"
echo "   连接 iPhone，选择设备后点击 Run"
echo ""
echo "3. iOS 真机构建（脚本方式）："
echo "   # 安装 ios-deploy"
echo "   npm install -g ios-deploy"
echo "   # 构建并安装"
echo "   ./scripts/build_native.sh ios-deploy"
echo ""
echo "4. macOS 构建："
echo "   ./scripts/build_native.sh macos-app"
echo ""
echo "注意：免费账号签名的应用有效期 7 天，到期后需要重新安装"
echo ""

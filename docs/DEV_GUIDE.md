# XExcalidraw 开发指南

## 快速开始

### 1. 环境准备

```bash
# 检查 Xcode
xcode-select -p
# 应该输出: /Applications/Xcode.app/Contents/Developer

# 检查 Node.js
node --version  # 需要 18+

# 安装依赖
cd web/canvas-host && npm install
```

### 2. 配置签名

#### 免费开发者账号（推荐初学者）

```bash
# 运行配置脚本
./scripts/setup_free_signing.sh

# 或手动配置
open apps/_legacy_xcode/ExcalidrawIOS.xcodeproj
# Xcode → Signing & Capabilities → Team → 选择 Apple ID
```

#### 付费开发者账号

```bash
# 编辑脚本设置签名证书
vim scripts/build_native.sh
# 修改: DEFAULT_IOS_SIGN_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)"
```

### 3. 构建运行

**iOS 模拟器：**
```bash
./scripts/build_native.sh ios-app
```

**iOS 真机（推荐用 Xcode）：**
```bash
# 方式 1: Xcode（最简单）
open apps/_legacy_xcode/ExcalidrawIOS.xcodeproj
# 连接 iPhone，选择设备，点击 Run

# 方式 2: 脚本（需要 ios-deploy）
npm install -g ios-deploy
./scripts/build_native.sh ios-deploy
```

**macOS：**
```bash
./scripts/build_native.sh macos-app
open build/native/macos/XExcalidraw.app
```

---

## 项目架构

### 目录结构

```
apps/
├── ios/                    # iOS SwiftUI 应用
│   ├── Package.swift       # SwiftPM 配置
│   └── Sources/
│       └── ExcalidrawIOS/
│           ├── App/        # App 入口
│           ├── Views/      # SwiftUI 视图
│           └── ...
│
├── macos/                  # macOS SwiftUI 应用
│   └── Sources/
│       └── ExcalidrawMac/
│
└── shared/                 # 共享代码
    └── Sources/
        └── ExcalidrawShared/
            ├── Models/     # 数据模型
            └── Bridge/     # 桥接类型

web/
└── canvas-host/            # React + Excalidraw
    ├── src/
    └── dist/               # 构建输出（自动复制到原生应用）
```

### 通信架构

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   SwiftUI App   │◄───►│   WKWebView     │◄───►│  Excalidraw   │
│                 │     │   (WebView)     │     │   (Web App)   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │
        ▼
┌─────────────────┐
│  DocumentStore  │  ← 文件存储（iCloud/本地）
└─────────────────┘
```

通信方式：
- Native → Web: `webView.evaluateJavaScript()`
- Web → Native: `window.webkit.messageHandlers`

---

## 开发工作流

### Web 开发模式

```bash
# 1. 启动 Web 开发服务器
cd web/canvas-host
npm run dev

# 2. 在 Xcode 中运行原生应用
# 应用会自动连接到 localhost:5173
```

### 原生开发模式

```bash
# 1. 构建 Web 资源
./scripts/build_web.sh

# 2. 构建并运行原生应用
./scripts/build_native.sh ios-app
```

### 完整构建（发布前）

```bash
# 清理并完整构建
rm -rf build .swiftpm/scratch
./scripts/build_native.sh ios-deploy  # iOS 真机
./scripts/build_native.sh macos-app   # macOS
```

---

## 签名详解

### 签名类型

| 类型 | 有效期 | 用途 |
|-----|-------|------|
| 模拟器 | 无需签名 | 开发调试 |
| 免费开发者 | 7 天 | 个人设备测试 |
| 付费开发者 | 1 年 | App Store 发布 |

### 签名流程

```
1. 开发: 使用 Apple Development 证书签名
2. 分发: 使用 Apple Distribution 证书签名
3. 设备: Provisioning Profile 包含设备 UDID
```

### 常见问题

**Q: 提示 "无法验证其完整性"**
- 免费账号：先在 Xcode 手动运行一次
- 检查设备是否信任开发者（设置 → 通用 → VPN与设备管理）

**Q: 提示 "No signing certificate"**
```bash
# 检查证书
security find-identity -v -p codesigning

# 检查 Xcode 中的 Team 设置
open apps/_legacy_xcode/ExcalidrawIOS.xcodeproj
```

**Q: 证书过期**
- 免费账号：删除旧 App，重新构建安装
- 付费账号：在 Apple Developer 续期 Provisioning Profile

---

## 调试技巧

### WebView 调试

```swift
// 在 App 中开启
#if DEBUG
webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
#endif
```

然后在 Safari → 开发 → 模拟器/设备 → 选择页面调试

### 日志查看

```bash
# iOS 设备日志
ios-deploy --bundle build/native/ios/XExcalidraw.app --debug

# macOS 控制台日志
log stream --predicate 'process == "XExcalidraw"'
```

---

## 发布构建

### iOS Ad Hoc 分发

```bash
# 1. 使用 Release 配置
CONFIGURATION=Release ./scripts/build_native.sh ios-device

# 2. 在 Xcode 中 Archive
open apps/_legacy_xcode/ExcalidrawIOS.xcodeproj
# Product → Archive → Distribute App
```

### macOS 分发

```bash
# 签名并公证
CONFIGURATION=Release ./scripts/build_native.sh macos-app

# 打包 DMG
create-dmg \
  --volname "XExcalidraw" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --app-drop-link 600 185 \
  "XExcalidraw.dmg" \
  "build/native/macos/XExcalidraw.app"
```

---

## 更多资源

- [桥接协议](bridge_protocol.md)
- [文件格式](file_format.md)
- [API 规范](excalidraw_native_spec_v1.md)

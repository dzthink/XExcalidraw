# XExcalidraw

跨平台的 Excalidraw 原生应用，支持 iOS 和 macOS，内置 Web 画布宿主。

## 项目结构

```
apps/
  ios/            # SwiftUI iOS 应用
  macos/          # SwiftUI macOS 应用  
  shared/         # 共享 Swift 包（模型 + 桥接类型）
web/
  canvas-host/    # React + Excalidraw 宿主应用
scripts/
  build_web.sh         # 构建 Web 宿主
  build_native.sh      # 构建原生应用（iOS/macOS）
  build_ios_device.sh  # iOS 真机构建（脚本方式）
  setup_free_signing.sh # 免费开发者账号配置
docs/
  bridge_protocol.md
  file_format.md
  excalidraw_native_spec_v1.md
```

## 前置要求

- **Xcode 15+**（支持 iOS 17/macOS 13+）
- **macOS 14+**
- **Node.js 18+**（用于构建 Web 宿主）
- **Apple ID**（免费开发者账号即可）

---

## 签名配置

### 方式一：付费开发者账号（推荐）

1. 在 Xcode → Settings → Accounts 登录 Apple ID
2. 确保有有效的 iOS Development 证书
3. 在 [Apple Developer](https://developer.apple.com) 创建 Provisioning Profile

### 方式二：免费开发者账号

```bash
# 运行配置脚本
./scripts/setup_free_signing.sh
```

或在 Xcode 中手动配置：
1. Xcode → 打开项目 `apps/_legacy_xcode/ExcalidrawIOS.xcodeproj`
2. 选中项目 → Signing & Capabilities
3. Team → 选择你的 Apple ID（Personal Team）
4. 勾选 Automatically manage signing
5. 连接设备后首次运行会提示信任，需在 iPhone 设置 → 通用 → VPN与设备管理中信任

**注意**：免费账号签名的应用有效期 7 天，需要每周重新安装。

---

## 构建说明

### 快速命令参考

| 命令 | 说明 |
|-----|------|
| `./scripts/build_native.sh ios-app` | iOS 模拟器构建 |
| `./scripts/build_native.sh ios-deploy` | iOS 真机构建+安装 |
| `./scripts/build_native.sh macos-app` | macOS 构建 |
| `./scripts/build_native.sh all` | 构建所有库 |

---

## 模拟器构建

### 方法 1：使用脚本（推荐）

```bash
# 构建 iOS 模拟器版本
./scripts/build_native.sh ios-app

# 构建并安装到运行中的模拟器
IOS_INSTALL=1 ./scripts/build_native.sh ios-app
```

### 方法 2：使用 Xcode

```bash
open apps/_legacy_xcode/ExcalidrawIOS.xcodeproj
```

1. 选择目标设备为 iOS Simulator
2. 点击 Run (Cmd+R)

---

## 真机构建

### 方法 1：使用 Xcode（最简单）

```bash
open apps/_legacy_xcode/ExcalidrawIOS.xcodeproj
```

1. 用 USB 连接 iPhone
2. 解锁 iPhone 并信任此电脑
3. Xcode 顶部选择你的 iPhone 设备
4. 点击 Run (Cmd+R)
5. 首次需要在 iPhone 上信任开发者（设置 → 通用 → VPN与设备管理）

### 方法 2：使用脚本 + ios-deploy

```bash
# 1. 安装 ios-deploy
npm install -g ios-deploy

# 2. 构建并安装到真机
./scripts/build_native.sh ios-deploy
```

**自动安装到指定设备**（多设备时）：
```bash
# 查看设备列表
ios-deploy --detect

# 指定设备安装
IOS_DEPLOY_ARGS="--id <设备UDID>" ./scripts/build_native.sh ios-deploy
```

### 方法 3：使用构建脚本配置

编辑 `scripts/build_native.sh` 前 20 行的默认配置：

```bash
# 你的 Apple Development 签名证书
# 查看：security find-identity -v -p codesigning
DEFAULT_IOS_SIGN_IDENTITY="Apple Development: your@email.com (XXXXXXXXXX)"

# Provisioning Profile 路径（付费账号需要）
DEFAULT_IOS_PROVISIONING_PROFILE="/path/to/your.mobileprovision"
```

然后运行：
```bash
./scripts/build_native.sh ios-device    # 只构建
./scripts/build_native.sh ios-deploy    # 构建并安装
```

---

## macOS 构建

```bash
# 使用脚本
./scripts/build_native.sh macos-app

# 或打开 Xcode 项目
open apps/_legacy_xcode/ExcalidrawMac.xcodeproj
```

构建产物：`build/native/macos/XExcalidraw.app`

---

## Web 宿主开发

```bash
cd web/canvas-host
npm install
npm run dev
```

开发服务器启动后，原生应用会自动连接到 `http://localhost:5173`。

### 构建 Web 宿主

```bash
./scripts/build_web.sh
```

Web 资源会被复制到原生应用的 Resources 目录中。

---

## 常见问题

### 1. "无法验证其完整性"

**原因**：签名失败或描述文件不匹配

**解决**：
- 确保在 Xcode 中选择了正确的 Team
- 免费账号需先在 Xcode 中手动运行一次，生成描述文件
- 在 iPhone 设置中信任开发者

### 2. "加载画布中" 卡住

**原因**：Web 资源未正确打包

**解决**：
```bash
rm -rf build/native
./scripts/build_native.sh ios-deploy
```

### 3. 找不到签名证书

```bash
# 查看可用证书
security find-identity -v -p codesigning
```

### 4. ios-deploy 安装失败

```bash
# 确保 iPhone 已连接并解锁
ios-deploy --detect

# 重新安装
./scripts/build_native.sh ios-deploy
```

---

## 技术细节

### Web 资源集成

- Xcode 构建时会自动调用 `./scripts/build_web.sh`
- Web 资源复制到 `Bundle.main.url(forResource: "index", withExtension: "html")`
- 如果 bundle 中不存在，应用会回退到 `http://localhost:5173`

### 桥接协议

原生应用与 Web 画布通过 WKWebView 的 `window.webkit.messageHandlers` 通信。详见 `docs/bridge_protocol.md`。

---

## License

MIT

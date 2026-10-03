# iPhone 真机验证

日期：2026-10-03。设备：iPhone 17，iOS 26.6.2。最终代码：本地主干 `533b258` 加工作区性能优化，包含搜索、全部文档、新建入口、列表对齐与新建按钮色调调整。Mind Elixir、Excalidraw 库源码、版本和锁文件未修改。

## 结果

- 最终完整 Debug 真机回归：11 项全部通过，0 失败、0 跳过；总测试耗时 510.224 秒。另行执行的最新 Release 正常配置启动检查也通过，应用已安装并启动，专用测试 Runner 已清理。
- 首轮 Debug 真机 UI 套件：9 项中 8 项通过；表格后续写丢失键盘焦点失败。覆盖底部搜索、全部文档、根目录及嵌套目录新建、编辑器打开返回、格式菜单、列表、键盘工具栏、文件夹选择。
- 新增 1000 节点隔离场景：大纲与导图均通过连续输入、滚动或双指缩放/拖动、返回、重开后的内容保留检查。用合成文档和独立偏好设置、索引、草稿目录，不修改用户原有文档。
- 焦点修复后的专门复测：导图、大纲的表格及代码后续写、长按添加/删除节点均通过。第一次仅调整 pointerdown 的修复仍失败；加入非 passive 的原生 touchstart 处理、取消默认触摸焦点切换后通过。命令保持在可信触摸事件中执行，下一帧只恢复文本选择。
- Release 真机启动检查通过：不加载测试夹具，使用设备现有设置进入正常应用。Release 版本已安装，应用标识保持 `com.excalidraw.ios`。
- Web 类型检查、21 项单元测试及生产构建通过；`git diff --check` 通过。修复后的 Web 资源已重新打包进 Release 应用。

初期结果来自分轮测试。最终重新执行完整套件后，11 项隔离行为检查在同一轮全部通过，包含新增真实九宫格输入测试；Release 启动检查另行运行。

## 性能与覆盖边界

1000 节点首次打开至 editor-ready 的两个自动化样本为 3.199 秒、3.246 秒，包含 XCTest 点击、等待、辅助功能快照开销，且为 Debug 构建；不能作为纯加载时长或 Release 性能基准。大图模式中 XCTest 获取辅助功能树明显更慢，手势命令的完整耗时也不能等同触摸响应延迟。

本轮证实真机交互及保存路径可用，并发现、修复了模拟器未暴露的焦点问题。真实九宫格输入检查在大纲标题中点系统字母键，再选择“你好”候选词，验证提交与返回重开保存；不是用 typeText 注入代替拼音输入。其他输入法、导图中的完整 composing 流程、大图片、真实 iCloud 下载/外部写入、长时间编辑仍需实测。

## 动画与主线程采样

在 1000 节点导图测试期间附加 Instruments Animation Hitches，得到 62.054 秒可用片段；覆盖拖动序列后半段、返回、重开和切换大纲，**没有覆盖连续输入或双指缩放**。初段大纲记录仅 1.307 秒，因测试重启应用而结束，排除出性能判断。

- 动画卡顿表记录 1 次 100.017ms 事件，标注 `Potentially expensive app update(s)`。
- 目标应用主线程表记录 11 项延迟标记，33.543–137.480ms；其中两项标注 Brief Unresponsiveness，为 137.480ms、106.083ms。
- 100ms 动画事件及 106ms 主线程事件的时间与切回大纲接近；137ms 主线程事件与返回后重开接近。一些 35ms 左右的事件与 XCTest 辅助功能树查询时间对齐。时间相关不能证明根因。

这说明千节点切换/重开仍有值得继续定位的短暂停顿，不能据此宣称所有交互已流畅达标。采样使用 Debug 应用与生产 Web 资源，并受到 XCTest 和 Instruments 的额外开销影响；没有 Release 对照、优化前真机基线、实际 FPS、掉帧率、内存峰值或温升测量。下一步应优先在 Release 下复现切换与重开，再确定应用集成层的优化方式。

已去掉设备标识与其他进程信息的数据：[真机动画采样](2026-10-03-iphone-animation.json)。原始 trace 留在 `/private/tmp/siye-iphone-map-animation.trace`。

## 本机原始记录

- 首轮：`/private/tmp/siye-iphone-signed-ui.xcresult`
- 大图与第一次焦点复测：`/private/tmp/siye-iphone-focused-ui.xcresult`
- 焦点修复成功复测：`/private/tmp/siye-iphone-touch-ui.xcresult`
- Release 启动：`/private/tmp/siye-iphone-release-smoke.xcresult`
- 最终完整 11 项回归：`/private/tmp/siye-iphone-complete.xcresult`
- 最新 Release 启动检查：`/private/tmp/siye-iphone-final-release-smoke.xcresult`
- Release 安装包：`/private/tmp/siye-iphone-release/Build/Products/Release-iphoneos/Siye.app`

截图已导出并检查，保留在 `/private/tmp/siye-iphone-*-attachments`，未将包含设备状态栏个人信息的原始截图复制进仓库。

可复用仓库 `ExcalidrawIOSUITests` scheme，指定真机 destination，构建参数为 `WEB_SKIP_BUILD=1`、`DEVELOPMENT_TEAM=KMP7VZJ6HC`、`CODE_SIGN_STYLE=Automatic`、`CODE_SIGN_IDENTITY=Apple Development`，并加 `-allowProvisioningUpdates`。测试 Runner 的仓库默认临时签名被命令行覆盖，项目签名设置没有修改。大图测试为 `testLargeMindMapEditingGesturesAndSave`，Release 正常启动检查为 `testReleaseLaunchSmoke`。

## 锁屏中断与后续复测

本地主干新增 `f190c4a`（全部文档与文件夹列表对齐）后重新构建，设备上的 Release 应用成功启动。追加完整回归中，底部搜索及编辑器打开两项通过；连续新建画布与导图在等待导图标题时失败，下一项测试明确被 Xcode 以设备锁屏为由暂停。当时未将该失败直接归因于锁屏或标为产品问题已经修复；后来持续解锁状态下重跑通过，详见下文。

暂停的运行已结束，原始记录为 `/private/tmp/siye-iphone-unlocked-full.xcresult`。为避免再次自动锁屏，Debug 隔离夹具现在设置 `UIApplication.shared.isIdleTimerDisabled = true`；普通使用和 Release 版本均不启用。解锁后连续新建复测通过，最终完整套件也通过，没有为此前的失败修改生产新建逻辑。

真实九宫格测试最初因按键标签带空格而跳过，之后因候选词实际为 Cell 而非 Button 修正定位；最终成功点系统按键与候选词并验证保存。测试未改变输入法设置。当前键盘没有九宫格字母键时会明确跳过；本次最终完整运行没有跳过项。最新测试包与运行文件位于 `/private/tmp/siye-iphone-ime`。
